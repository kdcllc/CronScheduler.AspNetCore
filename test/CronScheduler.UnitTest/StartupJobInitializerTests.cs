using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.StartupInitializer;

using Microsoft.Extensions.Logging;

using Moq;

using Xunit;

namespace CronScheduler.UnitTest;

public class StartupJobInitializerTests
{
    [Fact]
    public async Task StartJobsAsync_Runs_All_Jobs_In_Order_And_Logs_Completion()
    {
        var order = new List<string>();
        var (sut, logger) = Create(new RecordingJob(order, "first"), new RecordingJob(order, "second"));

        await sut.StartJobsAsync(TestContext.Current.CancellationToken);

        Assert.Equal(new[] { "first", "second" }, order);
        var logs = SchedulerCoverageTests.Logs(logger);
        Assert.Contains(logs, l => l.Level == LogLevel.Information && l.Message.Contains("start queuing 2 jobs"));
        Assert.Contains(logs, l => l.Level == LogLevel.Information && l.Message.Contains("completed queuing 2 jobs"));
        Assert.Equal(2, logs.Count(l => l.Level == LogLevel.Information && l.Message.EndsWith("RecordingJob completed")));
        Assert.DoesNotContain(logs, l => l.Level == LogLevel.Error);
    }

    [Fact]
    public async Task StartJobsAsync_With_No_Jobs_Logs_Zero_Count()
    {
        var (sut, logger) = Create();

        await sut.StartJobsAsync(TestContext.Current.CancellationToken);

        Assert.Contains(SchedulerCoverageTests.Logs(logger), l => l.Message.Contains("completed queuing 0 jobs"));
    }

    [Fact]
    public async Task StartJobsAsync_Failing_Job_Is_Logged_And_Following_Job_Still_Runs()
    {
        var order = new List<string>();
        var (sut, logger) = Create(
            new RecordingJob(order, "bad", new InvalidOperationException("kaboom")),
            new RecordingJob(order, "good"));

        await sut.StartJobsAsync(TestContext.Current.CancellationToken);

        Assert.Equal(new[] { "bad", "good" }, order);
        var logs = SchedulerCoverageTests.Logs(logger);
        var error = Assert.Single(logs, l => l.Level == LogLevel.Error);
        Assert.Contains("kaboom", error.Message);
        Assert.Contains(logs, l => l.Message.Contains("completed queuing 2 jobs"));
    }

    [Fact]
    public async Task StartJobsAsync_Cancelled_Token_Rethrows_And_Logs_Initialization_Failure()
    {
        var order = new List<string>();
        var (sut, logger) = Create(new RecordingJob(order, "never"));
        using var cts = new CancellationTokenSource();
        await cts.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => sut.StartJobsAsync(cts.Token));

        Assert.Empty(order);
        var logs = SchedulerCoverageTests.Logs(logger);
        var error = Assert.Single(logs, l => l.Level == LogLevel.Error);
        Assert.Contains("initialization failed", error.Message);
        Assert.DoesNotContain(logs, l => l.Message.Contains("completed queuing"));
    }

    private static (StartupJobInitializer Sut, Mock<ILogger> Logger) Create(params IStartupJob[] jobs)
    {
        var logger = new Mock<ILogger>();
        logger.Setup(l => l.IsEnabled(It.IsAny<LogLevel>())).Returns(true);
        var factory = new Mock<ILoggerFactory>();
        factory.Setup(f => f.CreateLogger(It.IsAny<string>())).Returns(logger.Object);
        return (new StartupJobInitializer(jobs, factory.Object), logger);
    }

    private sealed class RecordingJob(List<string> order, string name, Exception? toThrow = null) : IStartupJob
    {
        public Task ExecuteAsync(CancellationToken cancellationToken = default)
        {
            order.Add(name);
            if (toThrow != null)
            {
                throw toThrow;
            }

            return Task.CompletedTask;
        }
    }
}
