using System;
using System.Threading.Tasks;

using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using Xunit;

namespace CronScheduler.UnitTest;

public class StartupJobFuncTests
{
    [Fact]
    public async Task RunJobs()
    {
        using var host = Host.CreateDefaultBuilder()
            .ConfigureWebHostDefaults(builder => builder
                .UseStartup<TestStartup>()
                .ConfigureServices(services =>
                {
                    services.AddLogging();
                    services.AddStartupJob<TestStartupJob>();
                }))
            .UseDefaultServiceProvider(options => options.ValidateScopes = false)
            .Build();

        await host.RunStartupJobsAsync(TestContext.Current.CancellationToken);
        await host.StopAsync(TestContext.Current.CancellationToken);
    }

    [Fact]
    public async Task RunDelegate()
    {
        async Task CompletedTask() => await Task.CompletedTask;

        var host = CreateHost(services => services.AddStartupJobInitializer(CompletedTask));

        await host.RunStartupJobsAsync(TestContext.Current.CancellationToken);

        host.Dispose();
    }

    private static IHost CreateHost(Action<IServiceCollection> configureServices, bool validateScopes = false)
    {
        return Host.CreateDefaultBuilder()
            .ConfigureWebHostDefaults(builder => builder
                .UseStartup<TestStartup>()
                .ConfigureServices(configureServices))
            .UseDefaultServiceProvider(options => options.ValidateScopes = validateScopes)
            .Build();
    }
}
