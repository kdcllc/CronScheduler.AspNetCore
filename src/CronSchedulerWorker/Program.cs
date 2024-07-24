using System.Threading.Tasks;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CronSchedulerWorker;

public sealed class Program
{
    public static async Task Main(string[] args)
    {
        var host = CreateHostBuilder(args).Build();

        await host.RunStartupJobsAsync();

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

                // register a custom error processing for internal errors
                builder.AddUnobservedTaskExceptionHandler(sp =>
                {
                    var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger("CronJobs");

                    return
                        (sender, args) =>
                        {
                            logger?.LogError(args.Exception?.Message);
                            args.SetObserved();
                        };
                });
            });
        });
    }
}
