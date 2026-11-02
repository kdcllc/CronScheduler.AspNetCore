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

/// <summary>
/// Covers <see cref="SchedulerOptions.CronJitterSeed"/> and <see cref="SchedulerTaskWrapper.GetPreviousOccurrence"/>.
/// All assertions use fixed instants; the registration clock is never compared.
/// </summary>
public class SchedulerJitterTests
{
    private static readonly string JobName = nameof(TestJob);

    private static readonly DateTimeOffset FixedInstant = new(2026, 1, 1, 12, 30, 0, TimeSpan.Zero);

    private static ServiceProvider BuildProvider(Dictionary<string, string?> settings)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();

        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddLogging();
        services.AddScheduler(builder => builder.AddJob<TestJob>());

        return services.BuildServiceProvider();
    }

    private static Dictionary<string, string?> Settings(string cron, string? seed = null)
    {
        var dic = new Dictionary<string, string?>
        {
            { $"SchedulerJobs:{JobName}:CronSchedule", cron },
            { $"SchedulerJobs:{JobName}:CronTimeZone", "UTC" },
        };

        if (seed != null)
        {
            dic[$"SchedulerJobs:{JobName}:CronJitterSeed"] = seed;
        }

        return dic;
    }

    private static SchedulerRegistration CreateRegistration(out ServiceProvider provider, out TestJob job)
    {
        var services = new ServiceCollection();
        services.AddOptions();
        services.AddLogging();
        services.AddSingleton<SchedulerRegistration>();

        provider = services.BuildServiceProvider();
        job = new TestJob(provider.GetRequiredService<ILogger<TestJob>>());

        return provider.GetRequiredService<SchedulerRegistration>();
    }

    private static SchedulerTaskWrapper RegisterWithSeed(string cron, int? seed)
    {
        var registration = CreateRegistration(out var provider, out var job);
        using (provider)
        {
            var added = registration.AddOrUpdate(job, new SchedulerOptions { CronSchedule = cron, CronJitterSeed = seed, CronTimeZone = "UTC" });

            Assert.True(added);
            return registration.Jobs.Values.Single();
        }
    }

    [Fact]
    public void Config_CronJitterSeed_Binds_To_Registered_Job_Options()
    {
        using var sp = BuildProvider(Settings("H * * * *", "12345"));

        var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(JobName);

        Assert.Equal(12345, options.CronJitterSeed);
        Assert.Equal("H * * * *", options.CronSchedule);
    }

    [Fact]
    public void Config_CronJitterSeed_Absent_Is_Null()
    {
        using var sp = BuildProvider(Settings("0 */2 * * *"));

        var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(JobName);

        Assert.Null(options.CronJitterSeed);
        Assert.Null(new SchedulerOptions().CronJitterSeed);
    }

    [Fact]
    public void Config_Seed_Flows_Through_AddScheduler_Into_Registered_Wrapper()
    {
        using var sp = BuildProvider(Settings("H * * * *", "777"));

        var registration = sp.GetRequiredService<ISchedulerRegistration>();

        var wrapper = Assert.Single(registration.Jobs).Value;
        Assert.DoesNotContain("H", wrapper.Schedule.ToString());

        var expected = CronExpression.Parse("H * * * *", CronFormat.Standard, 777);
        Assert.Equal(
            expected.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc),
            wrapper.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc));
    }

    [Fact]
    public void Same_Seed_Gives_Same_Next_Occurrence_For_H_Schedule()
    {
        var first = RegisterWithSeed("H * * * *", 42);
        var second = RegisterWithSeed("H * * * *", 42);

        var firstNext = first.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc);
        var secondNext = second.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc);

        Assert.NotNull(firstNext);
        Assert.Equal(firstNext, secondNext);
        Assert.Equal(first.Schedule.ToString(), second.Schedule.ToString());
    }

    [Theory]
    [InlineData(1)]
    [InlineData(42)]
    [InlineData(99999)]
    public void Any_Seed_Gives_Next_Occurrence_Within_Next_Hour_Window(int seed)
    {
        var wrapper = RegisterWithSeed("H * * * *", seed);

        var next = wrapper.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc);

        Assert.NotNull(next);
        Assert.True(next > FixedInstant, $"{next} should be after {FixedInstant}");
        Assert.True(next <= FixedInstant.AddHours(1), $"{next} should be within one hour of {FixedInstant}");
        Assert.Equal(0, next!.Value.Second);
    }

    [Fact]
    public void Registered_H_Schedule_NextRunTime_Is_Aligned_To_Seeded_Minute()
    {
        var wrapper = RegisterWithSeed("H * * * *", 42);
        var seededMinute = wrapper.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc)!.Value.Minute;

        // The registration clock is not injectable, so assert only the clock-independent minute alignment.
        Assert.Equal(seededMinute, wrapper.NextRunTime.Minute);
        Assert.Equal(0, wrapper.NextRunTime.Second);
    }

    [Fact]
    public void No_Seed_Standard_Schedule_Uses_Standard_Next_Occurrence()
    {
        var wrapper = RegisterWithSeed("0 */2 * * *", null);

        var expected = new DateTimeOffset(2026, 1, 1, 14, 0, 0, TimeSpan.Zero);

        Assert.Equal(expected, wrapper.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc));
        Assert.Equal(
            CronExpression.Parse("0 */2 * * *").GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc),
            wrapper.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc));

        // Clock-independent shape of the registration-computed NextRunTime.
        Assert.Equal(0, wrapper.NextRunTime.Minute);
        Assert.Equal(0, wrapper.NextRunTime.Hour % 2);
    }

    [Fact]
    public void H_Schedule_Without_Seed_Throws_MissingSeedException_And_Job_Is_Not_Registered()
    {
        var registration = CreateRegistration(out var provider, out var job);
        using (provider)
        {
            // AddJob adds to the internal _jobs map before Create throws; the wrapped Jobs map stays empty.
            var ex = Assert.Throws<MissingSeedException>(() =>
                registration.AddOrUpdate(job, new SchedulerOptions { CronSchedule = "H * * * *", CronJitterSeed = null }));

            Assert.Contains("seed", ex.Message, StringComparison.OrdinalIgnoreCase);
            Assert.Empty(registration.Jobs);
        }
    }

    [Fact]
    public void H_Schedule_Without_Seed_In_Config_Throws_MissingSeedException_When_Registry_Resolved()
    {
        using var sp = BuildProvider(Settings("H * * * *"));

        Assert.Throws<MissingSeedException>(() => sp.GetRequiredService<ISchedulerRegistration>());
    }

    [Theory]
    [InlineData(14, true, 14)]
    [InlineData(14, false, 12)]
    [InlineData(13, true, 12)]
    [InlineData(13, false, 12)]
    public void GetPreviousOccurrence_Respects_Inclusive_Flag(int fromHour, bool inclusive, int expectedHour)
    {
        var wrapper = new SchedulerTaskWrapper(
            CronExpression.Parse("0 */2 * * *"),
            new TestJob(new LoggerFactory().CreateLogger<TestJob>()),
            new DateTimeOffset(2026, 1, 1, 14, 0, 0, TimeSpan.Zero),
            TimeZoneInfo.Utc);

        var from = new DateTimeOffset(2026, 1, 1, fromHour, fromHour == 13 ? 15 : 0, 0, TimeSpan.Zero);

        var previous = wrapper.GetPreviousOccurrence(from, inclusive);

        Assert.Equal(new DateTimeOffset(2026, 1, 1, expectedHour, 0, 0, TimeSpan.Zero), previous);
    }

    [Fact]
    public void GetPreviousOccurrence_Defaults_To_Exclusive()
    {
        var wrapper = new SchedulerTaskWrapper(
            CronExpression.Parse("0 */2 * * *"),
            new TestJob(new LoggerFactory().CreateLogger<TestJob>()),
            new DateTimeOffset(2026, 1, 1, 14, 0, 0, TimeSpan.Zero),
            TimeZoneInfo.Utc);

        var from = new DateTimeOffset(2026, 1, 1, 14, 0, 0, TimeSpan.Zero);

        Assert.Equal(new DateTimeOffset(2026, 1, 1, 12, 0, 0, TimeSpan.Zero), wrapper.GetPreviousOccurrence(from));
    }

    [Fact]
    public void GetPreviousOccurrence_For_Seeded_H_Schedule_Precedes_Next_By_One_Hour()
    {
        var wrapper = RegisterWithSeed("H * * * *", 42);

        var next = wrapper.Schedule.GetNextOccurrence(FixedInstant, TimeZoneInfo.Utc)!.Value;
        var previous = wrapper.GetPreviousOccurrence(next);

        Assert.Equal(next.AddHours(-1), previous);
        Assert.Equal(next, wrapper.GetPreviousOccurrence(next, inclusive: true));
    }
}
