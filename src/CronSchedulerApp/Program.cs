using System;
using System.Threading.Tasks;

using CronSchedulerApp.Jobs.Startup;

using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace CronSchedulerApp
{
    public sealed class Program
    {
        public static async Task Main(string[] args)
        {
            // run async jobs before the IWebHost run
            var host = CreateWebHostBuilder(args).Build();

            await host.RunStartupJobsAync();

            // await host.RunAsync();
            host.Run();
        }

        public static IWebHostBuilder CreateWebHostBuilder(string[] args)
        {
            return WebHost.CreateDefaultBuilder(args)
                    .ConfigureServices(services =>
                    {
                        services.AddStartupJob<SeedDatabaseStartupJob>();
                        services.AddStartupJob<TestStartupJob>();
                    })
                    .ConfigureLogging((context, logger) =>
                    {
                        logger.AddConsole();
                        logger.AddDebug();
                        logger.AddConfiguration(context.Configuration.GetSection("Logging"));
                    })
                    .UseShutdownTimeout(TimeSpan.FromSeconds(10)) // default is 5 seconds.
                    .UseStartup<Startup>();
        }
    }
}
