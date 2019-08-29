using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

using Cronos;

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CronScheduler.AspNetCore
{
    /// <summary>
    /// The implementation for <see cref="BackgroundService"/> service.
    /// </summary>
    public class SchedulerHostedService : BackgroundService
    {
        private readonly List<SchedulerTaskWrapper> _scheduledTasks = new List<SchedulerTaskWrapper>();
        private readonly TaskFactory _taskFactory = new TaskFactory(TaskScheduler.Current);
        private readonly bool _hasSecondsCron;
        private readonly ILogger<SchedulerHostedService> _logger;

        /// <summary>
        /// Initializes a new instance of the <see cref="SchedulerHostedService"/> class.
        /// </summary>
        /// <param name="scheduledTasks"></param>
        /// <param name="loggerFactory"></param>
        public SchedulerHostedService(
            IEnumerable<IScheduledJob> scheduledTasks,
            ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SchedulerHostedService>();

            var currentTimeUtc = DateTimeOffset.UtcNow;
            var timeZone = TimeZoneInfo.Local;

            foreach (var scheduledTask in scheduledTasks)
            {
                var taskName = scheduledTask.GetType().Name;

                if (string.IsNullOrEmpty(scheduledTask.CronSchedule))
                {
                    _logger.LogWarning("Task {taskName} does not have CRON. Task will not run.", taskName);

                    continue;
                }

                if (string.IsNullOrEmpty(scheduledTask.CronTimeZone))
                {
                    _logger.LogInformation("Task {taskName} is running under local time zone", taskName, timeZone.Id);
                }
                else
                {
                    try
                    {
                        timeZone = TimeZoneInfo.FindSystemTimeZoneById(scheduledTask.CronTimeZone);
                        _logger.LogInformation("Task {taskName} is running under local time zone {zoneId}", taskName, timeZone.Id);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError("Task {taskName} tried parse {zone} but failed with {ex} running under local time zone", taskName, scheduledTask.CronTimeZone, ex.Message);
                        timeZone = TimeZoneInfo.Local;
                    }
                }

                CronExpression crontabSchedule = null;

                if (scheduledTask.CronSchedule.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries).Length == 6)
                {
                    crontabSchedule = CronExpression.Parse(scheduledTask.CronSchedule, CronFormat.IncludeSeconds);
                    _hasSecondsCron = true;
                }
                else
                {
                    crontabSchedule = CronExpression.Parse(scheduledTask.CronSchedule, CronFormat.Standard);
                }

                var nextRunTime = scheduledTask.RunImmediately ? currentTimeUtc : crontabSchedule.GetNextOccurrence(currentTimeUtc, timeZone).Value;
                _scheduledTasks.Add(new SchedulerTaskWrapper(
                    crontabSchedule,
                    scheduledTask,
                    nextRunTime,
                    timeZone));
            }
        }

        public event EventHandler<UnobservedTaskExceptionEventArgs> UnobservedTaskException;

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                await ExecuteOnceAsync(stoppingToken);

                if (_hasSecondsCron)
                {
                    await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
                }
                else
                {
                    await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
                }
            }
        }

        private async Task ExecuteOnceAsync(CancellationToken stoppingToken)
        {
            var referenceTime = DateTimeOffset.UtcNow;

            var tasksThatShouldRun = _scheduledTasks.Where(t => t.ShouldRun(referenceTime)).ToList();

            foreach (var taskThatShouldRun in tasksThatShouldRun)
            {
                taskThatShouldRun.Increment();

#pragma warning disable CA2008 // Do not create tasks without passing a TaskScheduler
                await _taskFactory.StartNew(
                    async () =>
                    {
                        try
                        {
                            await taskThatShouldRun.ScheduledJob.ExecuteAsync(stoppingToken);
                        }
                        catch (Exception ex)
                        {
                            var args = new UnobservedTaskExceptionEventArgs(
                                ex as AggregateException ?? new AggregateException(ex));

                            UnobservedTaskException?.Invoke(this, args);

                            if (!args.Observed)
                            {
                                throw;
                            }
                        }
                    },
                    stoppingToken);
#pragma warning restore CA2008 // Do not create tasks without passing a TaskScheduler
            }
        }
    }
}
