using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Cronos;
using Microsoft.Extensions.Logging;

namespace CronScheduler.AspNetCore
{
    /// <summary>
    /// The implementation for <see cref="HostedServiceBase"/> service.
    /// </summary>
    public class SchedulerHostedService : HostedServiceBase
    {
        public event EventHandler<UnobservedTaskExceptionEventArgs> UnobservedTaskException;

        private readonly List<SchedulerTaskWrapper> _scheduledTasks = new List<SchedulerTaskWrapper>();
        private readonly TaskFactory _taskFactory = new TaskFactory(TaskScheduler.Current);
        private readonly bool _hasSecondsCron;

        /// <summary>
        /// Constructor for <see cref="SchedulerHostedService"/>
        /// </summary>
        /// <param name="scheduledTasks"></param>
        /// <param name="loggerFactory"></param>
        public SchedulerHostedService(IEnumerable<IScheduledJob> scheduledTasks, ILoggerFactory loggerFactory)
        {
            var logger = loggerFactory.CreateLogger<SchedulerHostedService>();

            var currentTimeUtc = DateTime.UtcNow;
            var timeZone = TimeZoneInfo.Local;

            foreach (var scheduledTask in scheduledTasks)
            {
                var taskName = scheduledTask.GetType().Name;

                if (string.IsNullOrEmpty(scheduledTask.CronSchedule))
                {
                    logger.LogWarning("Task {taskName} does not have CRON. Task will not run.", taskName);

                    continue;
                }

                if (string.IsNullOrEmpty(scheduledTask.CronTimeZone))
                {
                    logger.LogInformation("Task {taskName} is running under local time zone", taskName, timeZone.Id);
                }
                else
                {
                    try
                    {
                        timeZone = TimeZoneInfo.FindSystemTimeZoneById(scheduledTask.CronTimeZone);
                        logger.LogInformation("Task {taskName} is running under local time zone {zoneId}", taskName, timeZone.Id);
                    }
                    catch (Exception ex)
                    {
                        logger.LogError("Task {taskName} tried parse {zone} but failed with {ex} running under local time zone", taskName, scheduledTask.CronTimeZone, ex.Message);
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

                var nextRunTime = (scheduledTask.RunImmediately ? currentTimeUtc : crontabSchedule.GetNextOccurrence(currentTimeUtc, timeZone).Value);
                _scheduledTasks.Add(new SchedulerTaskWrapper(
                    crontabSchedule,
                    scheduledTask,
                    nextRunTime));
            }
        }

        protected override async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await ExecuteOnceAsync(cancellationToken);

                if (_hasSecondsCron)
                {
                    await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
                }
                else
                {
                    await Task.Delay(TimeSpan.FromMinutes(1), cancellationToken);
                }
            }
        }

        private async Task ExecuteOnceAsync(CancellationToken cancellationToken)
        {
            var referenceTime = DateTime.UtcNow;

            var tasksThatShouldRun = _scheduledTasks.Where(t => t.ShouldRun(referenceTime)).ToList();

            foreach (var taskThatShouldRun in tasksThatShouldRun)
            {
                taskThatShouldRun.Increment();

                await _taskFactory.StartNew(
                    async () =>
                    {
                        try
                        {
                            await taskThatShouldRun.ScheduledJob.ExecuteAsync(cancellationToken);
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
                    cancellationToken);
            }
        }
    }
}
