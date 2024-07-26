using System;
using System.Threading;
using System.Threading.Tasks;

using Bet.Extensions.Testing.Logging;

using CronScheduler.Extensions.Internal;
using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

using Xunit;
using Xunit.Abstractions;

namespace CronScheduler.UnitTest;

public class SchedulerRegistrationTests(ITestOutputHelper output)
{
    [Fact]
    public async Task Successfully_Register_Two_Jobs_With_The_Same_Type()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection().Build();

        var services = new ServiceCollection();

        services.AddSingleton<IConfiguration>(configuration);

        services.AddLogging(builder =>
        {
            builder.AddDebug();
            builder.AddXunit(output, LogLevel.Debug);
        });

        services.AddScheduler();
        services.AddHostedService<SchedulerHostedService>();

        var sp = services.BuildServiceProvider();
        var schedulerRegistration = sp.GetRequiredService<ISchedulerRegistration>();
        var loggerFactory = sp.GetRequiredService<ILoggerFactory>();

        var options1 = new CustomTestJobOptions
        {
            JobName = "Job1",
            CronSchedule = "0/2 * * * * *",
            RunImmediately = false,
            DisplayText = "Every 2 seconds."
        };

        var options2 = new CustomTestJobOptions
        {
            JobName = "Job2",
            CronSchedule = "0/4 * * * * *",
            RunImmediately = false,
            DisplayText = "Every 4 seconds."
        };

        schedulerRegistration.AddOrUpdate(new CustomTestJob(options1, loggerFactory.CreateLogger<CustomTestJob>()), options1);
        schedulerRegistration.AddOrUpdate(new CustomTestJob(options2, loggerFactory.CreateLogger<CustomTestJob>()), options2);

        var backgroundService = sp.GetService<IHostedService>() as SchedulerHostedService;
        await backgroundService!.StartAsync(CancellationToken.None);

        await Task.Delay(TimeSpan.FromSeconds(15));

        await backgroundService.StopAsync(CancellationToken.None);
    }
}
