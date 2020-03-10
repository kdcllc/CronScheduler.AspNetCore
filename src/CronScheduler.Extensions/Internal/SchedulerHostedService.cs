using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Hosting;

namespace CronScheduler.Extensions.Internal
{
    /// <summary>
    /// The implementation for <see cref="BackgroundService"/> service.
    /// </summary>
    internal class SchedulerHostedService : BackgroundService
    {
        private readonly TaskFactory _taskFactory = new TaskFactory(TaskScheduler.Current);
        private readonly ISchedulerRegistration _registrations;

        /// <summary>
        /// Initializes a new instance of the <see cref="SchedulerHostedService"/> class.
        /// </summary>
        /// <param name="registrations"></param>
        public SchedulerHostedService(ISchedulerRegistration registrations)
        {
            _registrations = registrations ?? throw new ArgumentNullException(nameof(registrations));
        }

        public event EventHandler<UnobservedTaskExceptionEventArgs>? UnobservedTaskException;

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                await ExecuteOnceAsync(stoppingToken);

                await Task.Delay(TimeSpan.FromSeconds(1), stoppingToken);
            }
        }

        private async Task ExecuteOnceAsync(CancellationToken stoppingToken)
        {
            var referenceTime = DateTimeOffset.UtcNow;

            var scheduledTasks = _registrations.Jobs.Values;
            var tasksThatShouldRun = scheduledTasks.Where(t => t.ShouldRun(referenceTime)).ToList();

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
