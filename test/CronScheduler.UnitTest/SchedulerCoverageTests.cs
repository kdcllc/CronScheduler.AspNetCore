using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;

using CronScheduler.Extensions.Internal;
using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

using Moq;

using Xunit;

namespace CronScheduler.UnitTest;

public class SchedulerCoverageTests
{
    private static readonly SchedulerOptions ValidOptions = new() { CronSchedule = "*/5 * * * *" };

    internal static List<(LogLevel Level, string Message, Exception? Exception)> Logs(Mock mock)
    {
        var result = new List<(LogLevel, string, Exception?)>();
        foreach (var inv in mock.Invocations.Where(i => i.Method.Name == nameof(ILogger.Log)))
        {
            var level = inv.Arguments[0] is LogLevel l
                ? l
                : throw new InvalidOperationException("Log invocation argument 0 is not a LogLevel.");
            var state = inv.Arguments[2];
            var ex = inv.Arguments[3] as Exception;
            var formatter = inv.Arguments[4] as Delegate
                ?? throw new InvalidOperationException("Log invocation argument 4 is not a formatter delegate.");
            var message = formatter.DynamicInvoke(state, ex) as string ?? string.Empty;
            result.Add((level, message, ex));
        }

        return result;
    }

    [Fact]
    public void AddOrUpdate_With_Options_Registers_Job_And_Replaces_On_Second_Call()
    {
        var (registration, _, _) = Create();
        var first = NewJob("a").Object;
        var second = NewJob("a").Object;

        Assert.True(registration.AddOrUpdate("my-job", first, ValidOptions));
        Assert.Same(first, registration.Jobs["my-job"].ScheduledJob);

        Assert.True(registration.AddOrUpdate("my-job", second, ValidOptions));

        Assert.Single(registration.Jobs);
        Assert.Same(second, registration.Jobs["my-job"].ScheduledJob);
    }

    [Fact]
    public void AddOrUpdate_Without_Options_Reads_Options_From_Monitor_By_Job_Name()
    {
        var (registration, _, monitor) = Create(new SchedulerOptions { CronSchedule = "0 0 * * *" });
        var job = NewJob("a").Object;

        Assert.True(registration.AddOrUpdate("named", job));

        Assert.Same(job, registration.Jobs["named"].ScheduledJob);
        monitor.Verify(m => m.Get("named"), Times.AtLeastOnce());
        var next = registration.Jobs["named"].NextRunTime;
        var local = TimeZoneInfo.ConvertTime(next, registration.Jobs["named"].TimeZoneInfo);
        Assert.Equal(0, local.Hour);
        Assert.Equal(0, local.Minute);
    }

    [Fact]
    public void AddOrUpdate_Without_Options_Replaces_Existing_Job()
    {
        var (registration, _, _) = Create();
        var first = NewJob("a").Object;
        var second = NewJob("a").Object;

        Assert.True(registration.AddOrUpdate("n", first));
        Assert.True(registration.AddOrUpdate("n", second));

        Assert.Single(registration.Jobs);
        Assert.Same(second, registration.Jobs["n"].ScheduledJob);
    }

    [Fact]
    public void AddOrUpdate_Using_Job_Name_Overloads_Register_Under_Job_Name()
    {
        var (registration, _, _) = Create();

        Assert.True(registration.AddOrUpdate(NewJob("by-name").Object));
        Assert.True(registration.AddOrUpdate(NewJob("by-name-opts").Object, ValidOptions));

        Assert.Contains("by-name", registration.Jobs.Keys);
        Assert.Contains("by-name-opts", registration.Jobs.Keys);
        Assert.Equal(2, registration.Jobs.Count);
    }

    [Fact]
    public void Constructor_Registers_Provided_Jobs()
    {
        var monitor = new Mock<IOptionsMonitor<SchedulerOptions>>();
        monitor.Setup(m => m.Get(It.IsAny<string>())).Returns(ValidOptions);
        var logger = new RegistrationLogger(new Mock<ILogger>().Object);

        var registration = new SchedulerRegistration(
            monitor.Object,
            new[] { NewJob("one").Object, NewJob("two").Object },
            logger);

        Assert.Equal(new[] { "one", "two" }, registration.Jobs.Keys.OrderBy(k => k));
    }

    [Fact]
    public void Constructor_Throws_On_Null_Dependencies()
    {
        var monitor = new Mock<IOptionsMonitor<SchedulerOptions>>();
        var logger = new RegistrationLogger(new Mock<ILogger>().Object);

        Assert.Throws<ArgumentNullException>(() => new SchedulerRegistration(null!, Array.Empty<IScheduledJob>(), logger));
        Assert.Throws<ArgumentNullException>(() => new SchedulerRegistration(monitor.Object, Array.Empty<IScheduledJob>(), null!));
    }

    [Fact]
    public void Options_Change_Rebuilds_Registered_Wrapper_Only_For_Known_Jobs()
    {
        var monitor = new Mock<IOptionsMonitor<SchedulerOptions>>();
        monitor.Setup(m => m.Get(It.IsAny<string>())).Returns(ValidOptions);
        Action<SchedulerOptions, string?>? listener = null;
        monitor.Setup(m => m.OnChange(It.IsAny<Action<SchedulerOptions, string?>>()))
            .Callback<Action<SchedulerOptions, string?>>(a => listener = a)
            .Returns(Mock.Of<IDisposable>());
        var logger = new RegistrationLogger(new Mock<ILogger>().Object);
        var registration = new SchedulerRegistration(monitor.Object, Array.Empty<IScheduledJob>(), logger);
        var job = NewJob("a").Object;
        registration.AddOrUpdate("j", job);
        var before = registration.Jobs["j"];

        Assert.NotNull(listener);
        listener!(new SchedulerOptions { CronSchedule = "0 0 1 1 *" }, "j");

        var after = registration.Jobs["j"];
        Assert.NotSame(before, after);
        Assert.Same(job, after.ScheduledJob);

        // unknown name and null name are ignored
        listener(new SchedulerOptions { CronSchedule = "0 0 1 1 *" }, "unknown");
        listener(new SchedulerOptions { CronSchedule = "0 0 1 1 *" }, null);
        Assert.Single(registration.Jobs);
        Assert.Same(after, registration.Jobs["j"]);
    }

    [Fact]
    public void Remove_Returns_True_For_Registered_Job_And_Removes_It()
    {
        var (registration, _, _) = Create();
        registration.AddOrUpdate("x", NewJob("x").Object, ValidOptions);

        Assert.True(registration.Remove("x"));

        Assert.Empty(registration.Jobs);
        Assert.False(registration.Remove("x"));
    }

    [Fact]
    public void Remove_Returns_False_For_Unknown_Job()
    {
        var (registration, _, _) = Create();
        registration.AddOrUpdate("x", NewJob("x").Object, ValidOptions);

        Assert.False(registration.Remove("nope"));
        Assert.Single(registration.Jobs);
    }

    [Fact]
    public void AddOrUpdate_With_Empty_Cron_Returns_False_And_Logs_Warning()
    {
        var (registration, logger, _) = Create();

        var added = registration.AddOrUpdate("nocron", NewJob("nocron").Object, new SchedulerOptions { CronSchedule = string.Empty });

        Assert.False(added);
        Assert.Empty(registration.Jobs);
        var warning = Assert.Single(Logs(logger), l => l.Level == LogLevel.Warning);
        Assert.Contains("nocron", warning.Message);
        Assert.Contains("does not have CRON", warning.Message);
    }

    [Fact]
    public void AddOrUpdate_With_Invalid_TimeZone_Registers_With_Local_And_Logs_Error()
    {
        var (registration, logger, _) = Create();

        var added = registration.AddOrUpdate(
            "tz",
            NewJob("tz").Object,
            new SchedulerOptions { CronSchedule = "*/5 * * * *", CronTimeZone = "Not/AZone" });

        Assert.True(added);
        Assert.Equal(TimeZoneInfo.Local, registration.Jobs["tz"].TimeZoneInfo);
        var error = Assert.Single(Logs(logger), l => l.Level == LogLevel.Error);
        Assert.Contains("Not/AZone", error.Message);
        Assert.Contains("tz", error.Message);
    }

    [Fact]
    public void AddOrUpdate_With_Valid_TimeZone_Uses_It_And_Logs_Information()
    {
        var (registration, logger, _) = Create();

        Assert.True(registration.AddOrUpdate(
            "utc",
            NewJob("utc").Object,
            new SchedulerOptions { CronSchedule = "*/5 * * * *", CronTimeZone = "UTC" }));

        Assert.Equal("UTC", registration.Jobs["utc"].TimeZoneInfo.Id);
        Assert.Contains(Logs(logger), l => l.Level == LogLevel.Information && l.Message.Contains("UTC"));
        Assert.DoesNotContain(Logs(logger), l => l.Level == LogLevel.Error);
    }

    [Fact]
    public void AddOrUpdate_With_Six_Part_Cron_Parses_Seconds_And_RunImmediately_Is_Now()
    {
        var (registration, _, _) = Create();
        var before = DateTimeOffset.UtcNow;

        Assert.True(registration.AddOrUpdate(
            "sec",
            NewJob("sec").Object,
            new SchedulerOptions { CronSchedule = "*/10 * * * * *", RunImmediately = true }));

        var wrapper = registration.Jobs["sec"];
        Assert.True(wrapper.NextRunTime >= before);
        Assert.True(wrapper.NextRunTime <= DateTimeOffset.UtcNow);
        var next = wrapper.Schedule.GetNextOccurrence(DateTimeOffset.UtcNow, TimeZoneInfo.Utc)!.Value;
        Assert.Equal(0, next.Second % 10);
    }

    [Fact]
    public void UnhandledException_Logs_Error_With_Job_Name_And_Exception()
    {
        var logger = new Mock<ILogger>();
        logger.Setup(l => l.IsEnabled(It.IsAny<LogLevel>())).Returns(true);
        var exception = new InvalidOperationException("boom");

        logger.Object.UnhandledException("job-x", exception);

        var entry = Assert.Single(Logs(logger));
        Assert.Equal(LogLevel.Error, entry.Level);
        Assert.Contains("job-x", entry.Message);
        Assert.Same(exception, entry.Exception);
    }

    [Fact]
    public void LoggerExtensions_Do_Not_Log_When_Level_Disabled()
    {
        var logger = new Mock<ILogger>();
        logger.Setup(l => l.IsEnabled(It.IsAny<LogLevel>())).Returns(false);

        logger.Object.UnhandledException("j", new Exception("x"));
        logger.Object.MissingCron("j", string.Empty);

        Assert.Empty(Logs(logger));
    }

    [Fact]
    public void AddScheduler_With_Handler_Resolves_Registration_And_HostedService_With_Handler()
    {
        EventHandler<UnobservedTaskExceptionEventArgs> handler = (_, _) => { };
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddOptions();

        services.AddScheduler(handler);

        using var sp = services.BuildServiceProvider();
        Assert.IsType<SchedulerRegistration>(sp.GetRequiredService<ISchedulerRegistration>());
        var hosted = Assert.Single(sp.GetServices<IHostedService>());
        Assert.IsType<SchedulerHostedService>(hosted);
        Assert.Contains(handler, GetHandlers(hosted));
    }

    [Fact]
    public void AddScheduler_With_Factory_Invokes_Factory_With_Provider_When_HostedService_Is_Built()
    {
        EventHandler<UnobservedTaskExceptionEventArgs> handler = (_, _) => { };
        IServiceProvider? received = null;
        var invocations = 0;
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddOptions();

        services.AddScheduler(sp =>
        {
            received = sp;
            invocations++;
            return handler;
        });

        using var provider = services.BuildServiceProvider();
        Assert.Equal(0, invocations);

        var hosted = Assert.Single(provider.GetServices<IHostedService>());

        Assert.Equal(1, invocations);
        Assert.NotNull(received);
        Assert.NotNull(received!.GetService<ISchedulerRegistration>());
        Assert.IsType<SchedulerHostedService>(hosted);
        Assert.Contains(handler, GetHandlers(hosted));
    }

    [Fact]
    public void AddScheduler_Without_Handler_Registers_Hosted_Service_Without_Handlers_And_Is_Not_Duplicated()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddOptions();

        services.AddScheduler();
        services.AddScheduler();

        using var sp = services.BuildServiceProvider();
        var hosted = Assert.Single(sp.GetServices<IHostedService>());
        Assert.Empty(GetHandlers(hosted));
    }

    private static Delegate[] GetHandlers(IHostedService hosted)
    {
        var field = typeof(SchedulerHostedService).GetField(
            nameof(SchedulerHostedService.UnobservedTaskException),
            BindingFlags.Instance | BindingFlags.NonPublic)!;
        var del = (Delegate?)field.GetValue(hosted);
        return del?.GetInvocationList() ?? Array.Empty<Delegate>();
    }

    private static (SchedulerRegistration Registration, Mock<ILogger> Logger, Mock<IOptionsMonitor<SchedulerOptions>> Monitor) Create(
        SchedulerOptions? monitorOptions = null)
    {
        var monitor = new Mock<IOptionsMonitor<SchedulerOptions>>();
        monitor.Setup(m => m.Get(It.IsAny<string>())).Returns(monitorOptions ?? ValidOptions);

        var logger = new Mock<ILogger>();
        logger.Setup(l => l.IsEnabled(It.IsAny<LogLevel>())).Returns(true);

        var registration = new SchedulerRegistration(monitor.Object, Array.Empty<IScheduledJob>(), new RegistrationLogger(logger.Object));
        return (registration, logger, monitor);
    }

    private static Mock<IScheduledJob> NewJob(string name)
    {
        var job = new Mock<IScheduledJob>();
        job.SetupGet(j => j.Name).Returns(name);
        return job;
    }

    // Moq cannot proxy ILogger<internal type>, so forward to a mockable non-generic ILogger.
    private sealed class RegistrationLogger(ILogger inner) : ILogger<SchedulerRegistration>
    {
        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull
        {
            return inner.BeginScope(state);
        }

        public bool IsEnabled(LogLevel logLevel)
        {
            return inner.IsEnabled(logLevel);
        }

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            inner.Log(logLevel, eventId, state, exception, formatter);
        }
    }
}
