using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.AspNetCore;

using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

namespace Microsoft.Extensions.DependencyInjection
{
    public static class StartupJobsServiceCollectionExtensions
    {
        /// <summary>
        /// Runs async all of the registered <see cref="IStartupJob"/> jobs.
        /// </summary>
        /// <param name="host"></param>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        public static async Task RunStartupJobsAync(this IWebHost host, CancellationToken cancellationToken = default)
        {
            using (var scope = host.Services.CreateScope())
            {
                var jobInitializer = scope.ServiceProvider.GetRequiredService<StartupJobInitializer>();
                await jobInitializer.StartJobsAsync(cancellationToken);
            }
        }

        /// <summary>
        /// Runs async all of the registered <see cref="IStartupJob"/> jobs.
        /// </summary>
        /// <param name="host"></param>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        public static async Task RunStartupJobsAync(this IHost host, CancellationToken cancellationToken = default)
        {
            using (var scope = host.Services.CreateScope())
            {
                var jobInitializer = scope.ServiceProvider.GetRequiredService<StartupJobInitializer>();
                await jobInitializer.StartJobsAsync(cancellationToken);
            }
        }

        /// <summary>
        /// Adds task to run as async job before the rest of the application launches.
        /// </summary>
        /// <param name="services"></param>
        /// <param name="job"></param>
        /// <returns></returns>
        public static IServiceCollection AddStartupJobInitializer(this IServiceCollection services, Func<Task> job)
        {
            return services.AddStartupJobInitializer()
                .AddSingleton<IStartupJob>(new DelegateStartupJobInitializer(job));
        }

        /// <summary>
        /// Adds <see cref="StartupJobInitializer"/> to DI registration.
        /// </summary>
        /// <param name="services"></param>
        /// <returns></returns>
        public static IServiceCollection AddStartupJobInitializer(this IServiceCollection services)
        {
            services.TryAddTransient<StartupJobInitializer>();
            return services;
        }

        /// <summary>
        /// Adds <see cref="IStartupJob"/> job to the DI registration.
        /// </summary>
        /// <typeparam name="TStartupJob"></typeparam>
        /// <param name="services"></param>
        /// <returns></returns>
        public static IServiceCollection AddStartupJob<TStartupJob>(this IServiceCollection services)
            where TStartupJob : class, IStartupJob
        {
            return services
                .AddStartupJobInitializer()
                .AddTransient<IStartupJob, TStartupJob>();
        }

        private class DelegateStartupJobInitializer : IStartupJob
        {
            private readonly Func<Task> _startupJob;

            public DelegateStartupJobInitializer(Func<Task> startupJob)
            {
                _startupJob = startupJob;
            }

            public Task ExecuteAsync(CancellationToken cancellationToken = default)
            {
                return _startupJob();
            }
        }
    }
}
