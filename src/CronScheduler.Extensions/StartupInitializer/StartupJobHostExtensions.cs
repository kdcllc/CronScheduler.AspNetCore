using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.StartupInitializer;

using Microsoft.Extensions.DependencyInjection;

namespace Microsoft.Extensions.Hosting
{
    public static class StartupJobHostExtensions
    {
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
    }
}
