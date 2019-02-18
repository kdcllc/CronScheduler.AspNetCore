using CronScheduler.AspNetCore;

namespace Microsoft.Extensions.DependencyInjection
{
    public static class BackgroundQueuedExtensions
    {
        /// <summary>
        /// Adds Background Queued Hosted service.
        /// </summary>
        /// <param name="services"></param>
        /// <returns></returns>
        public static IServiceCollection AddQueuedService(this IServiceCollection services)
        {
            services.AddHostedService<QueuedHostedService>();
            services.AddSingleton<IBackgroundTaskQueue, BackgroundTaskQueue>();

            return services;
        }
    }
}
