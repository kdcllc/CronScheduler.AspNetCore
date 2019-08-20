using System;
using System.Threading.Tasks;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace CronScheduler
{
    public sealed class Program
    {
        public static void Main(string[] args)
        {
            CreateHostBuilder(args).Build().Run();
        }

        public static IHostBuilder CreateHostBuilder(string[] args)
        {
            return Host.CreateDefaultBuilder(args)
            .ConfigureServices(services =>
            {
                services.AddHostedService<Worker>();

                // services.AddSchedulerJob<TestJob, TestJobOptions>();
                services.AddScheduler(builder =>
                {
                    builder.AddJob<TestJob, TestJobOptions>();
                    builder.UnobservedTaskExceptionHandler = UnobservedHandler;
                });
            });
        }

        private static void UnobservedHandler(object sender, UnobservedTaskExceptionEventArgs e)
        {
            Console.WriteLine(e.Exception.GetBaseException());
            e.SetObserved();
        }
    }
}
