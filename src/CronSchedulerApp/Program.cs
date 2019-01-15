using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System.Threading.Tasks;

namespace CronSchedulerApp
{
#pragma warning disable RCS1102 // Make class static.
    public class Program
#pragma warning restore RCS1102 // Make class static.
    {
        public static async Task Main(string[] args)
        {
            var host = CreateWebHostBuilder(args).Build();

            // process any async jobs required to get the site up and running
            await host.RunStartupJobsAync();

            host.Run();
        }

        public static IWebHostBuilder CreateWebHostBuilder(string[] args)
        {
            return WebHost.CreateDefaultBuilder(args)
                    .ConfigureServices(services =>
                    {
                        services.AddStartupJob<SeedDatabaseJob>();
                        services.AddStartupJob<TestStartupJob>();
                    })
                    .ConfigureLogging((context, logger) =>
                    {
                        logger.AddConsole();
                        logger.AddDebug();
                        logger.AddConfiguration(context.Configuration.GetSection("Logging"));
                    })
                    .UseStartup<Startup>();
        }
    }
}
