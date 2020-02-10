using System;
using System.Threading.Tasks;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace CronSchedulerWorker
{
    public sealed class Program
    {
        public static async Task Main(string[] args)
        {
            var host = CreateHostBuilder(args).Build();

            await host.RunStartupJobsAync();

            await host.RunAsync();
        }

        public static IHostBuilder CreateHostBuilder(string[] args)
        {
            return Host.CreateDefaultBuilder(args)
            .ConfigureServices(services =>
            {
                services.AddStartupJob<TestStartupJob>();

                services.AddScheduler(builder =>
                {
                    builder.AddJob<TestJob, TestJobOptions>();
                    builder.UnobservedTaskExceptionHandler = UnobservedHandler;
                });
            });
        }

        private static void UnobservedHandler(object sender, UnobservedTaskExceptionEventArgs e)
        {
            Console.WriteLine(e.Exception?.GetBaseException());
            e.SetObserved();
        }
    }
}
