using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.BackgroundTask;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

using Moq;

using Xunit;

namespace CronScheduler.UnitTest;

public class BackgroundQueuedServiceTests
{
    private static readonly TimeSpan PollTimeout = TimeSpan.FromSeconds(30);

    [Fact]
    public async Task QueuedHostedService_Runs_Work_Item_And_Marks_Complete()
    {
        var context = new BackgroundTaskContext();
        var queue = new BackgroundTaskQueue(context);
        var logs = new CapturingLogger<QueuedHostedService>();
        using var lifetime = new LifetimeStub();
        var service = CreateService(queue, context, lifetime, logs);

        var ran = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        queue.QueueBackgroundWorkItem(
            _ =>
            {
                ran.TrySetResult(true);
                return Task.CompletedTask;
            },
            "ok-item");

        Assert.Equal(1, context.Count);

        await service.StartAsync(TestContext.Current.CancellationToken);
        try
        {
            Assert.True(await ran.Task.WaitAsync(PollTimeout, TestContext.Current.CancellationToken));
            await WaitUntilAsync(() => context.Count == 0);
            Assert.True(context.IsComplete);
        }
        finally
        {
            await service.StopAsync(CancellationToken.None);
        }
    }

    [Fact]
    public async Task QueuedHostedService_Failing_Item_Invokes_OnException_Logs_Error_And_Continues()
    {
        var context = new BackgroundTaskContext();
        var queue = new BackgroundTaskQueue(context);
        var logs = new CapturingLogger<QueuedHostedService>();
        using var lifetime = new LifetimeStub();
        var service = CreateService(queue, context, lifetime, logs);

        var boom = new InvalidOperationException("boom");
        Exception? received = null;
        var handled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var secondRan = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        queue.QueueBackgroundWorkItem(
            _ => throw boom,
            "failing-item",
            ex =>
            {
                received = ex;
                handled.TrySetResult(true);
            });
        queue.QueueBackgroundWorkItem(
            _ =>
            {
                secondRan.TrySetResult(true);
                return Task.CompletedTask;
            },
            "second-item");

        await service.StartAsync(TestContext.Current.CancellationToken);
        try
        {
            Assert.True(await handled.Task.WaitAsync(PollTimeout, TestContext.Current.CancellationToken));
            Assert.True(await secondRan.Task.WaitAsync(PollTimeout, TestContext.Current.CancellationToken));

            Assert.NotNull(received);
            Assert.Contains("encountered error while executing failing-item task", received!.Message);
            Assert.Same(boom, received.InnerException);

            await WaitUntilAsync(() => logs.Entries.Any(e => e.Level == LogLevel.Error));
            var error = logs.Entries.First(e => e.Level == LogLevel.Error);
            Assert.Same(boom, error.Exception);
            Assert.Contains("failing-item", error.Message);
        }
        finally
        {
            await service.StopAsync(CancellationToken.None);
        }
    }

    [Fact]
    public async Task QueuedHostedService_Start_And_Stop_Log_And_Complete_Execution()
    {
        var context = new BackgroundTaskContext();
        var queue = new BackgroundTaskQueue(context);
        var logs = new CapturingLogger<QueuedHostedService>();
        using var lifetime = new LifetimeStub();
        var service = CreateService(queue, context, lifetime, logs);

        await service.StartAsync(TestContext.Current.CancellationToken);

        Assert.Contains(logs.Entries, e => e.Level == LogLevel.Debug && e.Message.Contains("is starting."));
        Assert.DoesNotContain(logs.Entries, e => e.Message.Contains("is stopping."));
        Assert.NotNull(service.ExecuteTask);
        Assert.False(service.ExecuteTask!.IsCompleted);

        await service.StopAsync(CancellationToken.None).WaitAsync(PollTimeout, TestContext.Current.CancellationToken);

        Assert.Contains(logs.Entries, e => e.Level == LogLevel.Debug && e.Message.Contains("is stopping."));
        await WaitUntilAsync(() => service.ExecuteTask.IsCompleted);
        Assert.False(service.ExecuteTask.IsFaulted);
        Assert.Same(queue, service.TaskQueued);
    }

    [Fact]
    public async Task OnApplicationStopping_Wait_Disabled_Returns_Without_Entering()
    {
        var context = new BackgroundTaskContext();
        context.RegisterTask(); // outstanding work that would block if waiting were enabled
        var queue = new BackgroundTaskQueue(context);
        var logs = new CapturingLogger<QueuedHostedService>();
        using var lifetime = new LifetimeStub();
        _ = CreateService(queue, context, lifetime, logs, enableWait: false);

        await Task.Run(lifetime.Stop, TestContext.Current.CancellationToken)
            .WaitAsync(PollTimeout, TestContext.Current.CancellationToken);

        Assert.DoesNotContain(logs.Entries, e => e.Message.Contains("is entered"));
        Assert.DoesNotContain(logs.Entries, e => e.Message.Contains("is waiting"));
    }

    [Fact]
    public async Task OnApplicationStopping_Wait_Enabled_Waits_Until_Context_Complete()
    {
        var context = new BackgroundTaskContext();
        context.RegisterTask();
        var queue = new BackgroundTaskQueue(context);
        var logs = new CapturingLogger<QueuedHostedService>();
        using var lifetime = new LifetimeStub();
        _ = CreateService(queue, context, lifetime, logs, enableWait: true, waitTimeout: TimeSpan.FromMilliseconds(50));

        var stopping = Task.Run(lifetime.Stop, TestContext.Current.CancellationToken);

        await WaitUntilAsync(() => logs.Entries.Any(e => e.Message.Contains("is waiting")));
        Assert.False(stopping.IsCompleted);

        context.MarkAsComplete();

        await stopping.WaitAsync(PollTimeout, TestContext.Current.CancellationToken);
        Assert.Contains(logs.Entries, e => e.Message.Contains("is entered"));
        Assert.Contains(logs.Entries, e => e.Message.Contains("is waiting"));
    }

    [Fact]
    public void AddBackgroundQueuedService_Defaults_Are_Applied()
    {
        using var provider = BuildProvider(s => s.AddBackgroundQueuedService());

        var options = provider.GetRequiredService<IOptionsMonitor<QueuedHostedServiceOptions>>().CurrentValue;

        Assert.False(options.EnableApplicationOnStopWait);
        Assert.Equal(TimeSpan.FromSeconds(10), options.ApplicationOnStopWaitTimeout);
    }

    [Fact]
    public void AddBackgroundQueuedService_Explicit_Values_Are_Applied()
    {
        using var provider = BuildProvider(s => s.AddBackgroundQueuedService(true, TimeSpan.FromSeconds(3)));

        var options = provider.GetRequiredService<IOptionsMonitor<QueuedHostedServiceOptions>>().CurrentValue;

        Assert.True(options.EnableApplicationOnStopWait);
        Assert.Equal(TimeSpan.FromSeconds(3), options.ApplicationOnStopWaitTimeout);
    }

    [Fact]
    public void AddBackgroundQueuedService_Registers_Expected_Services()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        var returned = services.AddBackgroundQueuedService();
        Assert.Same(services, returned);

        using var provider = BuildProvider(s => s.AddBackgroundQueuedService());

        var queue1 = provider.GetRequiredService<IBackgroundTaskQueue>();
        var queue2 = provider.GetRequiredService<IBackgroundTaskQueue>();
        Assert.IsType<BackgroundTaskQueue>(queue1);
        Assert.Same(queue1, queue2);

        Assert.NotNull(provider.GetRequiredService<BackgroundTaskContext>());

        var hosted = provider.GetServices<IHostedService>();
        Assert.Contains(hosted, h => h is QueuedHostedService);
    }

    [Fact]
    public void BackgroundTaskContext_Register_And_Complete_Update_State()
    {
        var context = new BackgroundTaskContext();

        Assert.Equal(0, context.Count);
        Assert.True(context.IsComplete);

        context.RegisterTask();
        context.RegisterTask();
        Assert.Equal(2, context.Count);
        Assert.False(context.IsComplete);

        context.MarkAsComplete();
        Assert.Equal(1, context.Count);
        Assert.False(context.IsComplete);

        context.MarkAsComplete();
        Assert.Equal(0, context.Count);
        Assert.True(context.IsComplete);
    }

    [Fact]
    public async Task BackgroundTaskQueue_OnException_Overload_Enqueues_With_Empty_Name_And_Callback()
    {
        var context = new BackgroundTaskContext();
        using var queue = new BackgroundTaskQueue(context);
        Action<Exception> callback = _ => { };
        Func<CancellationToken, Task> work = _ => Task.CompletedTask;

        queue.QueueBackgroundWorkItem(work, callback);

        Assert.Equal(1, context.Count);
        var (workItem, workItemName, onException) = await queue.DequeueAsync(TestContext.Current.CancellationToken);
        Assert.Equal(string.Empty, workItemName);
        Assert.Same(callback, onException);
        Assert.Same(work, workItem);
    }

    [Fact]
    public void BackgroundTaskQueue_Null_WorkItem_Throws_And_Does_Not_Register()
    {
        var context = new BackgroundTaskContext();
        using var queue = new BackgroundTaskQueue(context);

        var ex = Assert.Throws<ArgumentNullException>(
            () => queue.QueueBackgroundWorkItem(null!, _ => { }));

        Assert.Equal("workItem", ex.ParamName);
        Assert.Equal(0, context.Count);
    }

    private static ServiceProvider BuildProvider(Action<IServiceCollection> configure)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(new Mock<IHostApplicationLifetime>().Object);
        configure(services);
        return services.BuildServiceProvider();
    }

    private static QueuedHostedService CreateService(
        IBackgroundTaskQueue queue,
        BackgroundTaskContext context,
        LifetimeStub lifetime,
        CapturingLogger<QueuedHostedService> logger,
        bool enableWait = false,
        TimeSpan? waitTimeout = null)
    {
        var factory = new Mock<ILoggerFactory>();
        factory.Setup(f => f.CreateLogger(It.IsAny<string>())).Returns(logger);

        var options = new Mock<IOptionsMonitor<QueuedHostedServiceOptions>>();
        options.Setup(o => o.CurrentValue).Returns(new QueuedHostedServiceOptions
        {
            EnableApplicationOnStopWait = enableWait,
            ApplicationOnStopWaitTimeout = waitTimeout ?? TimeSpan.FromSeconds(10),
        });

        return new QueuedHostedService(queue, factory.Object, context, lifetime.Mock.Object, options.Object);
    }

    private static async Task WaitUntilAsync(Func<bool> predicate)
    {
        var deadline = DateTime.UtcNow + PollTimeout;
        while (!predicate())
        {
            if (DateTime.UtcNow > deadline)
            {
                Assert.Fail("Timed out waiting for condition.");
            }

            await Task.Delay(50, TestContext.Current.CancellationToken);
        }
    }

    private sealed class LifetimeStub : IDisposable
    {
        private readonly CancellationTokenSource _stopping = new();

        public LifetimeStub()
        {
            Mock.Setup(l => l.ApplicationStopping).Returns(_stopping.Token);
        }

        public Mock<IHostApplicationLifetime> Mock { get; } = new();

        public void Stop()
        {
            _stopping.Cancel();
        }

        public void Dispose()
        {
            _stopping.Dispose();
        }
    }

    private sealed record LogEntry(LogLevel Level, string Message, Exception? Exception);

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        private readonly ConcurrentQueue<LogEntry> _entries = new();

        public IReadOnlyCollection<LogEntry> Entries => _entries.ToArray();

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull
        {
            return null;
        }

        public bool IsEnabled(LogLevel logLevel)
        {
            return true;
        }

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            _entries.Enqueue(new LogEntry(logLevel, formatter(state, exception), exception));
        }
    }
}
