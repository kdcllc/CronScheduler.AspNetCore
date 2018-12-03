using System;
using System.Threading.Tasks;
using CronScheduler.AspNetCore;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Microsoft.Extensions.DependencyInjection
{
    /// <summary>
    /// An Extension method to register <see cref="SchedulerHostedService"/>.
    /// https://github.com/aspnet/Hosting/blob/a3dd609ae667adcb6eb062125d76f9a76a82f7b4/src/Microsoft.Extensions.Hosting.Abstractions/ServiceCollectionHostedServiceExtensions.cs#L17
    /// </summary>
    public static class CronSchedulerExtensions
    {

        public static IServiceCollection AddScheduler(this IServiceCollection services)
        {
            return services.AddTransient<IHostedService,SchedulerHostedService>();
        }

        public static IServiceCollection AddScheduler(this IServiceCollection services,
            EventHandler<UnobservedTaskExceptionEventArgs> unobservedTaskExceptionHandler)
        {
            return services.AddTransient<IHostedService,SchedulerHostedService>(serviceProvider =>
            {
                var loggerFactory = serviceProvider.GetService<ILoggerFactory>();
                var scheduledJobs = serviceProvider.GetServices<IScheduledJob>();

                var instance = new SchedulerHostedService(scheduledJobs, loggerFactory);
                instance.UnobservedTaskException += unobservedTaskExceptionHandler;

                return instance;
            });
        }
    }
}
