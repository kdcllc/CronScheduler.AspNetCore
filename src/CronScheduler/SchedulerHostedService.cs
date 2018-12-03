using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CronScheduler.AspNetCore.Cron;
using Microsoft.Extensions.Logging;

namespace CronScheduler.AspNetCore
{
    public class SchedulerHostedService : HostedServiceBase
    {
        public event EventHandler<UnobservedTaskExceptionEventArgs> UnobservedTaskException;

        private readonly List<SchedulerTaskWrapper> _scheduledTasks = new List<SchedulerTaskWrapper>();
        private readonly TaskFactory _taskFactory = new TaskFactory(TaskScheduler.Current);

        public SchedulerHostedService(IEnumerable<IScheduledJob> scheduledTasks, ILoggerFactory loggerFactory)
        {
            var logger = loggerFactory.CreateLogger<SchedulerHostedService>();

            var currentTimeUtc = DateTime.UtcNow;

            foreach (var scheduledTask in scheduledTasks)
            {
                if (string.IsNullOrEmpty(scheduledTask.CronSchedule))
                {
                    var taskName = scheduledTask.GetType().Name;
                    logger.LogWarning("Task {taskName} does not have CRON. Task will not run.", taskName);

                    continue;
                }

                var crontabSchedule = CrontabSchedule.Parse(scheduledTask.CronSchedule);

                _scheduledTasks.Add(new SchedulerTaskWrapper
                {
                    Schedule = crontabSchedule,
                    Task = scheduledTask,
                    NextRunTime = scheduledTask.RunImmediately ? currentTimeUtc : crontabSchedule.GetNextOccurrence(currentTimeUtc)
                });
            }
        }

        protected override async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await ExecuteOnceAsync(cancellationToken);

                await Task.Delay(TimeSpan.FromMinutes(1), cancellationToken);
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
                            await taskThatShouldRun.Task.ExecuteAsync(cancellationToken);
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
