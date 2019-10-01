using System;
using System.Linq;

using CronScheduler.Extensions.BackgroundTask;

namespace Microsoft.Extensions.DependencyInjection
{
    public static class BackgroundQueuedServiceCollectionExtensions
    {
        private static readonly BackgroundTaskContext _sharedContext = new BackgroundTaskContext();

        /// <summary>
        /// Adds Background Queued Hosted service.
        /// </summary>
        /// <param name="services">The instance of <see cref="IServiceCollection"/>.</param>
        /// <param name="applicationOnStopWaitForTasksToComplete">The flag to enable or disable wait for the background queued tasks to complete before application shutdowns. Default is false.</param>
        /// <param name="applicationOnStopTimeoutWait">The <see cref="TimeSpan"/> timeout to wait for the background queued tasks to complete. Default is 10 seconds.</param>
        /// <returns></returns>
        public static IServiceCollection AddBackgroundQueuedService(
            this IServiceCollection services,
            bool applicationOnStopWaitForTasksToComplete = false,
            TimeSpan applicationOnStopTimeoutWait = default)
        {
            applicationOnStopTimeoutWait = applicationOnStopTimeoutWait == default ? TimeSpan.FromSeconds(10) : applicationOnStopTimeoutWait;

            services.Configure<QueuedHostedServiceOptions>(opt =>
            {
                opt.EnableApplicationOnStopWait = applicationOnStopWaitForTasksToComplete;
                opt.ApplicationOnStopWaitTimeout = applicationOnStopTimeoutWait;
            });

            // Add the singleton StartupTaskContext only once
            if (services.Any(x => x.ServiceType != typeof(BackgroundTaskContext)))
            {
                services.AddSingleton(_sharedContext);
            }

            services.AddHostedService<QueuedHostedService>();
            services.AddSingleton<IBackgroundTaskQueue, BackgroundTaskQueue>();

            return services;
        }
    }
}
