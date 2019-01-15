using CronScheduler.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection.Extensions;
using System.Threading.Tasks;

namespace Microsoft.Extensions.DependencyInjection
{
    public static class StartupJobExtensions
    {
        /// <summary>
        /// Runs async all of the registered <see cref="IStartupJob"/> jobs.
        /// </summary>
        /// <param name="host"></param>
        /// <returns></returns>
        public static async Task RunStartupJobsAync(this IWebHost host)
        {
            using (var scope = host.Services.CreateScope())
            {
                var jobInitializer = scope.ServiceProvider.GetRequiredService<StartupJobInitializer>();
                await jobInitializer.StartJobsAsync();
            }
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
            where TStartupJob: class, IStartupJob
        {
            return services
                .AddStartupJobInitializer()
                .AddTransient<IStartupJob, TStartupJob>();
        }
    }
}
