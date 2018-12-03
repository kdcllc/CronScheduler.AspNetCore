using CronScheduler.AspNetCore;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace Microsoft.Extensions.DependencyInjection
{
    /// <summary>
    /// An Extension method to register <see cref="SchedulerHostedService"/>.
    /// https://github.com/aspnet/Hosting/blob/a3dd609ae667adcb6eb062125d76f9a76a82f7b4/src/Microsoft.Extensions.Hosting.Abstractions/ServiceCollectionHostedServiceExtensions.cs#L17
    /// </summary>
    public static class CronSchedulerExtensions
    {
        /// <summary>
        /// Adds <see cref="SchedulerHostedService"/> service without global error handler.
        /// </summary>
        /// <param name="services"></param>
        /// <returns></returns>
        public static IServiceCollection AddScheduler(this IServiceCollection services)
        {
            CreateInstance(services);
            return services;
        }

        /// <summary>
        /// Adds <see cref="SchedulerHostedService"/> service with global error handler.
        /// </summary>
        /// <param name="services"></param>
        /// <param name="unobservedTaskExceptionHandler"></param>
        /// <returns></returns>
        public static IServiceCollection AddScheduler(
            this IServiceCollection services,
            EventHandler<UnobservedTaskExceptionEventArgs> unobservedTaskExceptionHandler)
        {
            CreateInstance(services, unobservedTaskExceptionHandler);
            return services;
        }

        /// <summary>
        /// Adds <see cref="SchedulerHostedService"/> service with ability to register all of the cron job inside the context.
        /// </summary>
        /// <param name="services"></param>
        /// <param name="config"></param>
        /// <returns></returns>
        public static IServiceCollection AddScheduler(
            this IServiceCollection services,
            Action<SchedulerBuilder> config
            )
        {
            var builder = new SchedulerBuilder(services);
            config(builder);

            CreateInstance(services, builder.UnobservedTaskExceptionHandler);
            return services;
        }

        private static void CreateInstance(
            IServiceCollection services,
            EventHandler<UnobservedTaskExceptionEventArgs> unobservedTaskExceptionHandler=null)
        {
            services.AddTransient<IHostedService,SchedulerHostedService>(serviceProvider =>
            {
                var loggerFactory = serviceProvider.GetService<ILoggerFactory>();
                var scheduledJobs = serviceProvider.GetServices<IScheduledJob>();

                var instance = new SchedulerHostedService(scheduledJobs, loggerFactory);

                if (unobservedTaskExceptionHandler != null)
                {
                    instance.UnobservedTaskException += unobservedTaskExceptionHandler;
                }
                return instance;
            });
        }
    }
}
