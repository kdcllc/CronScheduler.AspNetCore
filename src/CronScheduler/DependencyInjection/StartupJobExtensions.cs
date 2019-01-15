using CronScheduler.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using System.Threading.Tasks;

namespace Microsoft.Extensions.DependencyInjection
{
    public static class StartupJobExtensions
    {
        public static async Task ProcessStartUpJobs(this IWebHost host)
        {
            using (var scope = host.Services.CreateScope())
            {
                var jobInitializer = scope.ServiceProvider.GetRequiredService<StartupJobInitializer>();
                await jobInitializer.StartJobsAsync();
            }
        }

        public static IServiceCollection AddStartupJobInitializer(this IServiceCollection services)
        {
            services.AddTransient<StartupJobInitializer>();
            return services;
        }

        public static IServiceCollection AddStartupJob<TStartupJob>(this IServiceCollection services) where TStartupJob: class, IStartupJob
        {
            return services
                .AddStartupJobInitializer()
                .AddTransient<IStartupJob, TStartupJob>();
        }
    }
}
