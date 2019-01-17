using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace CronScheduler.UnitTest
{
    public class StartupJobFuncTests
    {
        [Fact]
        public async Task RunJobs()
        {
            var cts = new CancellationTokenSource();

            var builder = WebHost.CreateDefaultBuilder()
               .UseStartup<TestStartup>()
               .ConfigureServices(services =>
               {
                   services.AddLogging();
                   services.AddStartupJob<TestStartupJob>();
               })
               .UseDefaultServiceProvider(options => options.ValidateScopes = false);

            var host = builder.Build();

            using (host)
            {
                await host.RunStartupJobsAync(cts.Token);

                cts.Cancel();

                await host.WaitForShutdownAsync(cts.Token);
            }
        }

        [Fact]
        public async Task RunDelegate()
        {
            async Task task() => await Task.CompletedTask;

            var host = CreateHost(services => services.AddStartupJobInitializer(task));

            await host.RunStartupJobsAync();
        }

        private static IWebHost CreateHost(Action<IServiceCollection> configureServices, bool validateScopes = false)
        {
            return new WebHostBuilder()
                    .UseStartup<TestStartup>()
                    .ConfigureServices(configureServices)
                    .UseDefaultServiceProvider(options => options.ValidateScopes = validateScopes)
                    .Build();
        }
    }
}
