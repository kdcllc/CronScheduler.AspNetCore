using System;
using System.Collections.Generic;
using System.Linq;

using Cronos;

using CronScheduler.Extensions.Internal;
using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

using Xunit;

namespace CronScheduler.UnitTest;

public class SchedulerServiceTests(ITestOutputHelper output)
{
    [Fact]
    public void Add_Job_Successfully()
    {
        var dic = new Dictionary<string, string?>
        {
            { "SchedulerJobs:TestJobException:CronSchedule", "*/10 * * * * *" },
            { "SchedulerJobs:TestJobException:CronTimeZone", string.Empty },
            { "SchedulerJobs:TestJobException:RunImmediately", "true" },
        };

        var configuration = new ConfigurationBuilder().AddInMemoryCollection(dic).Build();

        var services = new ServiceCollection();

        services.AddSingleton<IConfiguration>(configuration);

        services.AddOptions();

        var name = typeof(TestJob).Name;

        services.AddOptions<SchedulerOptions>(name)
            .Configure<IConfiguration>((options, configuration) =>
            {
                configuration.Bind("SchedulerJobs:TestJobException", options);
            });

        services.AddLogging(builder =>
        {
            builder.AddConsole();
            builder.AddDebug();
        });

        services.AddSingleton<SchedulerRegistration>();

        var sp = services.BuildServiceProvider();

        var instance = sp.GetService<SchedulerRegistration>();

        using var logFactory = LoggerFactory.Create(builder =>
        {
            builder.AddConsole();
            builder.AddDebug();
        });

        var job = new TestJob(logFactory.CreateLogger<TestJob>());
        var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(name);

        instance!.AddOrUpdate(job.GetType().Name, job, options);

        Assert.Single(instance.Jobs);
    }

    [Fact]
    public void Add_Job_Successfully_1()
    {
        var dic = new Dictionary<string, string?>
        {
            { "SchedulerJobs:TestJobException:CronSchedule", "*/10 * * * * *" },
            { "SchedulerJobs:TestJobException:CronTimeZone", string.Empty },
            { "SchedulerJobs:TestJobException:RunImmediately", "true" },
        };

        var configuration = new ConfigurationBuilder().AddInMemoryCollection(dic).Build();

        var service = new ServiceCollection();

        service.AddSingleton<IConfiguration>(configuration);

        service.AddOptions();

        var name = typeof(TestJob).Name;

        service.AddChangeTokenOptions<SchedulerOptions>("SchedulerJobs:TestJobException", name, _ => { });

        service.AddLogging(builder =>
        {
            builder.AddConsole();
            builder.AddDebug();
        });

        service.AddSingleton<SchedulerRegistration>();

        var sp = service.BuildServiceProvider();

        var instance = sp.GetService<SchedulerRegistration>();

        using var logFactory = LoggerFactory.Create(builder =>
        {
            builder.AddConsole();
            builder.AddDebug();
        });

        var job = new TestJob(logFactory.CreateLogger<TestJob>());
        var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(name);

        instance!.AddOrUpdate(job.GetType().Name, job, options);

        Assert.Single(instance.Jobs);

        configuration.Providers.ToList()[0].Set("SchedulerJobs:TestJobException:CronSchedule", "*/1 * * * * *");
        configuration.Reload();

        output.WriteLine(instance.Jobs.ToArray()[0].Value.Schedule.ToString());
    }

    [Fact]
    public void Add_Job_With_Deterministic_Jitter_Successfully()
    {
        var services = new ServiceCollection();
        services.AddOptions();
        services.AddLogging();
        services.AddSingleton<SchedulerRegistration>();

        using var serviceProvider = services.BuildServiceProvider();
        var registration = serviceProvider.GetRequiredService<SchedulerRegistration>();
        var logger = serviceProvider.GetRequiredService<ILogger<TestJob>>();
        var options = new SchedulerOptions
        {
            CronSchedule = "H * * * * *",
            CronJitterSeed = 12345
        };

        var added = registration.AddOrUpdate(new TestJob(logger), options);

        Assert.True(added);
        Assert.Single(registration.Jobs);
        Assert.DoesNotContain("H", registration.Jobs.Values.Single().Schedule.ToString());
    }

    [Fact]
    public void Get_Previous_Occurrence_Successfully()
    {
        using var loggerFactory = LoggerFactory.Create(builder => builder.AddDebug());
        var schedule = CronExpression.Parse("* * * * *");
        var wrapper = new SchedulerTaskWrapper(
            schedule,
            new TestJob(loggerFactory.CreateLogger<TestJob>()),
            new DateTimeOffset(2026, 1, 1, 12, 1, 0, TimeSpan.Zero),
            TimeZoneInfo.Utc);

        var previous = wrapper.GetPreviousOccurrence(new DateTimeOffset(2026, 1, 1, 12, 0, 30, TimeSpan.Zero));

        Assert.Equal(new DateTimeOffset(2026, 1, 1, 12, 0, 0, TimeSpan.Zero), previous);
    }
}
