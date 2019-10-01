using System;
using System.Threading.Tasks;

using CronSchedulerApp.Jobs.Startup;

using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CronSchedulerApp
{
    public sealed class Program
    {
        public static async Task Main(string[] args)
        {
            // run async jobs before the IWebHost run
            // AspNetCore 2.x syntaxn of the registration.
            // var host = CreateWebHostBuilder(args).Build();
            var host = CreateHostBuilder(args).Build();

            await host.RunStartupJobsAync();

            await host.RunAsync();
        }

        public static IHostBuilder CreateHostBuilder(string[] args)
        {
            return Host.CreateDefaultBuilder(args)
                    .ConfigureWebHostDefaults(webBuilder =>
                    {
                        webBuilder.UseStartup<Startup>();

                        webBuilder.ConfigureServices(services =>
                        {
                            services.AddStartupJob<SeedDatabaseStartupJob>();
                            services.AddStartupJob<TestStartupJob>();
                        });
                    })
                    .ConfigureLogging((context, logger) =>
                    {
                        logger.AddConsole();
                        logger.AddDebug();
                        logger.AddConfiguration(context.Configuration.GetSection("Logging"));
                    });
        }

        /// <summary>
        /// AspNetCore 2.x syntaxn of the registration.
        /// </summary>
        /// <param name="args"></param>
        /// <returns></returns>
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
