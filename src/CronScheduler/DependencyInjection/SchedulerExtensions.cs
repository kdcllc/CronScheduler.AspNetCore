using System;
using System.Threading.Tasks;

using CronScheduler.AspNetCore;

using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Microsoft.Extensions.DependencyInjection
{
    /// <summary>
    /// An Extension method to register <see cref="SchedulerHostedService"/>.
    /// https://github.com/aspnet/Hosting/blob/a3dd609ae667adcb6eb062125d76f9a76a82f7b4/src/Microsoft.Extensions.Hosting.Abstractions/ServiceCollectionHostedServiceExtensions.cs#L17.
    /// </summary>
    public static class SchedulerExtensions
    {
        /// <summary>
        /// Adds <see cref="SchedulerHostedService"/> service without global error handler <see cref="UnobservedTaskExceptionEventArgs"/>.
        /// Manually register jobs.
        /// </summary>
        /// <param name="services"></param>
        /// <returns></returns>
        public static IServiceCollection AddScheduler(this IServiceCollection services)
        {
            CreateInstance(services);
            return services;
        }

        /// <summary>
        /// Adds <see cref="SchedulerHostedService"/> service with global error handler <see cref="UnobservedTaskExceptionEventArgs"/>.
        /// Manually register jobs.
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
        /// Adds <see cref="SchedulerHostedService"/> service with ability to register all of the cron job inside the context with
        /// global error handler <see cref="UnobservedTaskExceptionEventArgs"/>.
        /// </summary>
        /// <param name="services"></param>
        /// <param name="config"></param>
        /// <returns></returns>
        public static IServiceCollection AddScheduler(
            this IServiceCollection services,
            Action<SchedulerBuilder> config)
        {
            var builder = new SchedulerBuilder(services);
            config(builder);

            CreateInstance(builder.Services, builder.UnobservedTaskExceptionHandler);

            return builder.Services;
        }

        /// <summary>
        /// Adds <see cref="IScheduledJob"/> job to DI without support for <see cref="UnobservedTaskExceptionEventArgs"/> delegate.
        /// </summary>
        /// <typeparam name="TJob"></typeparam>
        /// <typeparam name="TJobOptions"></typeparam>
        /// <param name="services"></param>
        /// <param name="sectionName"></param>
        /// <returns></returns>
        public static IServiceCollection AddSchedulerJob<TJob, TJobOptions>(
            this IServiceCollection services,
            string sectionName = "SchedulerJobs")
            where TJob : class, IScheduledJob
            where TJobOptions : SchedulerOptions, new()
        {
            var builder = new SchedulerBuilder(services);

            // add job with configuration settings
            builder.AddJob<TJob, TJobOptions>(sectionName);

            CreateInstance(builder.Services);

            return builder.Services;
        }

        private static void CreateInstance(
            IServiceCollection services,
            EventHandler<UnobservedTaskExceptionEventArgs> unobservedTaskExceptionHandler = null)
        {
            // should prevent from double registrations.
            services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, SchedulerHostedService>(sp =>
            {
                var loggerFactory = sp.GetService<ILoggerFactory>();
                var scheduledJobs = sp.GetServices<IScheduledJob>();

                var instance = new SchedulerHostedService(scheduledJobs, loggerFactory);

                if (unobservedTaskExceptionHandler != null)
                {
                    instance.UnobservedTaskException += unobservedTaskExceptionHandler;
                }

                return instance;
            }));
        }
    }
}
