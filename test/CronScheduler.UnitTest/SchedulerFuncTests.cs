using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

using Moq;

using Xunit;

namespace CronScheduler.UnitTest;

public class SchedulerFuncTests
{
    [Fact]
    public async Task Job_RunImmediately_Factory_Successfully()
    {
        // assign
        using var logFactory = LoggerFactory.Create(builder =>
        {
            builder.AddConsole();
            builder.AddDebug();
        });

        var mockLoggerTestJob = new Mock<ILogger<TestJob>>();

        var host = CreateHost(services =>
        {
            var jobName = nameof(TestJob);

            services.AddScheduler(ctx =>
            {
                ctx.AddJob(
                    sp => new TestJob(mockLoggerTestJob.Object),
                    options =>
                    {
                        options.CronSchedule = "*/5 * * * * *";
                        options.RunImmediately = true;
                    },
                    jobName: jobName);
            });
        });

        var client = host.GetTestClient();

        // act
        var response = await client.GetAsync("/hc", TestContext.Current.CancellationToken);
        response.EnsureSuccessStatusCode();
        await WaitForLogsAsync(mockLoggerTestJob, LogLevel.Information, nameof(TestJob), 1);

        // assert
        Assert.Equal("healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));

        mockLoggerTestJob.Verify(
            l => l.Log(
            LogLevel.Information,
            It.IsAny<EventId>(),
            It.Is<It.IsAnyType>((object? v, Type _) => v != null && v.ToString()!.Contains(nameof(TestJob))),
            It.IsAny<Exception>(),
            It.Is<Func<object, Exception?, string>>((v, t) => true)),
            Times.AtLeastOnce());
    }

    [Fact]
    public async Task Same_Job_RunImmediately_Factory_Two_Different_Options_Successfully()
    {
        // assign
        var mockLoggerTestJob = new Mock<ILogger<TestJobDup>>();

        var host = CreateHost(services =>
        {
            services.AddScheduler(ctx =>
            {
                var jobName1 = "TestJob1";

                ctx.AddJob(
                    sp =>
                    {
                        var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(jobName1);
                        return new TestJobDup(options, mockLoggerTestJob.Object);
                    },
                    options =>
                    {
                        options.CronSchedule = "*/5 * * * * *";
                        options.RunImmediately = true;
                    },
                    jobName: jobName1);

                var jobName2 = "TestJob2";

                ctx.AddJob(
                    sp =>
                    {
                        var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(jobName2);
                        return new TestJobDup(options, mockLoggerTestJob.Object);
                    }, options =>
                    {
                        options.CronSchedule = "*/5 * * * * *";
                        options.RunImmediately = true;
                    },
                    jobName: jobName2);
            });
        });

        var client = host.GetTestClient();

        // act
        var response = await client.GetAsync("/hc", TestContext.Current.CancellationToken);
        response.EnsureSuccessStatusCode();
        await WaitForLogsAsync(mockLoggerTestJob, LogLevel.Information, nameof(TestJob), 2);

        // assert
        Assert.Equal("healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));

        mockLoggerTestJob.Verify(
                l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((object? v, Type _) => v != null && v.ToString()!.Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.Is<Func<object, Exception?, string>>((v, t) => true)),
                Times.AtLeast(2));
    }

    [Fact]
    public async Task Job_RunImmediately_Configuration_Successfully()
    {
        // assign
        var mockLoggerTestJob = new Mock<ILogger<TestJob>>();

        var host = CreateHost(services =>
        {
            services.AddScheduler(ctx =>
            {
                ctx.AddJob<TestJob>();
            });

            services.AddTransient(x => mockLoggerTestJob.Object);
        });

        var client = host.GetTestClient();

        // act
        var response = await client.GetAsync("/hc", TestContext.Current.CancellationToken);
        response.EnsureSuccessStatusCode();
        await WaitForLogsAsync(mockLoggerTestJob, LogLevel.Information, nameof(TestJob), 1);

        // assert
        Assert.Equal("healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));

        mockLoggerTestJob.Verify(
                l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((object? v, Type _) => v != null && v.ToString()!.Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.Is<Func<object, Exception?, string>>((v, t) => true)),
                Times.AtLeastOnce());
    }

    [Fact]
    public async Task Job_RunDelayed_Factory_Successfully()
    {
        var mockLogger = new Mock<ILogger<TestJob>>();

        var host = CreateHost(services =>
        {
            services.AddScheduler(ctx =>
            {
                var jobName = nameof(TestJob);

                ctx.AddJob(
                    sp => new TestJob(mockLogger.Object),
                    configure: options =>
                    {
                        options.CronSchedule = "*/05 * * * * *";
                        options.RunImmediately = false;
                    },
                    jobName: jobName);
            });
        });

        var client = host.GetTestClient();

        // act
        var response = await client.GetAsync("/hc", TestContext.Current.CancellationToken);
        response.EnsureSuccessStatusCode();
        await WaitForLogsAsync(mockLogger, LogLevel.Information, nameof(TestJob), 1);

        // assert
        Assert.Equal("healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));

        // fixed moq and log according to https://github.com/moq/moq4/issues/918#issuecomment-535060645
        mockLogger.Verify(
            l => l.Log(
            LogLevel.Information,
            It.IsAny<EventId>(),
            It.Is<It.IsAnyType>((object? v, Type _) => v != null && v.ToString()!.Contains(nameof(TestJob))),
            It.IsAny<Exception>(),
            It.Is<Func<object, Exception?, string>>((v, t) => true)),
            Times.AtLeastOnce());
    }

    [Fact]
    public async Task Job_RunDelayed_And_Raise_UnobservedTaskException()
    {
        // arrange
        var mockLogger = new Mock<ILogger<TestJobException>>();

        var host = CreateHost(services =>
        {
            services.AddScheduler(ctx =>
            {
                var jobName = nameof(TestJobException);

                ctx.AddUnobservedTaskExceptionHandler(sp => (sender, args) => UnobservedTaskExceptionHandler(sp, args));

                ctx.AddJob<TestJobException, TestJobExceptionOptions>(
                    sp =>
                    {
                        var options = sp.GetRequiredService<IOptionsMonitor<TestJobExceptionOptions>>();
                        return new TestJobException(mockLogger.Object, options);
                    },
                    options =>
                    {
                        options.CronSchedule = "*/4 * * * * *";
                        options.RunImmediately = false;
                        options.JobName = jobName;
                        options.RaiseException = true;
                    },
                    jobName: jobName);
            });
        });

        var client = host.GetTestClient();

        // act
        var response = await client.GetAsync("/hc", TestContext.Current.CancellationToken);
        response.EnsureSuccessStatusCode();
        await WaitForLogsAsync(mockLogger, LogLevel.Error, nameof(Exception), 1);

        // assert
        Assert.Equal("healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));

        mockLogger.Verify(
            l => l.Log(
                    LogLevel.Error,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((object? v, Type _) => v != null && v.ToString()!.Contains(nameof(Exception))),
                    It.IsAny<Exception>(),
                    It.Is<Func<object, Exception?, string>>((v, t) => true)),
            Times.AtLeastOnce());
    }

    [Fact]
    public async Task Job_RunDelayed_And_Raise_UnobservedTaskException_Via_Delegate()
    {
        // arrange
        var mockLogger = new Mock<ILogger<TestJobException>>();
        var host = CreateHost(services =>
        {
            services.AddScheduler(ctx =>
            {
                var jobName = nameof(TestJobException);

                ctx.AddUnobservedTaskExceptionHandler(sp => (sender, args) => UnobservedTaskExceptionHandler(sp, args));

                ctx.AddJob<TestJobException, TestJobExceptionOptions>(
                    sp =>
                    {
                        var options = sp.GetRequiredService<IOptionsMonitor<TestJobExceptionOptions>>();
                        return new TestJobException(mockLogger.Object, options);
                    },
                    options =>
                    {
                        options.CronSchedule = "*/4 * * * * *";
                        options.RunImmediately = false;
                        options.JobName = jobName;
                        options.RaiseException = true;
                    },
                    jobName: jobName);
            });
        });

        var client = host.GetTestClient();

        // act
        var response = await client.GetAsync("/hc", TestContext.Current.CancellationToken);
        response.EnsureSuccessStatusCode();
        await WaitForLogsAsync(mockLogger, LogLevel.Error, nameof(Exception), 1);

        // assert
        Assert.Equal("healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));

        mockLogger.Verify(
            l => l.Log(
                LogLevel.Error,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((object? v, Type _) => v != null && v.ToString()!.Contains(nameof(Exception))),
                It.IsAny<Exception>(),
                It.Is<Func<object, Exception?, string>>((v, t) => true)),
            Times.AtLeastOnce());
    }

    [Fact]
    public async Task Job_RunImmediately_Configuration_And_Raise_Exception()
    {
        // arrange
        var mockLogger = new Mock<ILogger<TestJobException>>();

        var host = CreateHost(services =>
        {
            // used for tests
            services.AddTransient(x => mockLogger.Object);

            // short registration without UnobservedTaskExceptionHandler
            services.AddSchedulerJob<TestJobException, TestJobExceptionOptions>();
        });

        var client = host.GetTestClient();

        // act
        var response = await client.GetAsync("/hc", TestContext.Current.CancellationToken);
        response.EnsureSuccessStatusCode();
        await WaitForLogsAsync(mockLogger, LogLevel.Error, nameof(Exception), 1);

        // assert
        Assert.Equal("healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));

        mockLogger.Verify(
            l => l.Log(
                LogLevel.Error,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((object? v, Type _) => v != null && v.ToString()!.Contains(nameof(Exception))),
                It.IsAny<Exception>(),
                It.Is<Func<object, Exception?, string>>((v, t) => true)),
            Times.AtLeastOnce());
    }

    /// <summary>
    /// Polls the mock logger until at least <paramref name="minCount"/> log invocations with the given
    /// level and message fragment are recorded; fails the test when the timeout elapses.
    /// </summary>
    /// <returns>The number of matching invocations observed when the condition was met.</returns>
    private static async Task<int> WaitForLogsAsync<T>(
        Mock<ILogger<T>> mockLogger,
        LogLevel level,
        string messageContains,
        int minCount,
        TimeSpan? timeout = null)
    {
        var limit = timeout ?? TimeSpan.FromSeconds(30);
        var deadline = DateTime.UtcNow + limit;
        var count = 0;

        while (true)
        {
            count = mockLogger.Invocations.Count(i =>
                i.Method.Name == nameof(ILogger.Log)
                && i.Arguments.Count > 2
                && i.Arguments[0] is LogLevel l
                && l == level
                && (i.Arguments[2]?.ToString()?.Contains(messageContains) ?? false));

            if (count >= minCount)
            {
                return count;
            }

            if (DateTime.UtcNow >= deadline)
            {
                Assert.Fail($"Expected at least {minCount} {level} log(s) containing '{messageContains}' within {limit.TotalSeconds}s but observed {count}.");
            }

            await Task.Delay(TimeSpan.FromMilliseconds(100), TestContext.Current.CancellationToken);
        }
    }

    private IHost CreateHost(
        Action<IServiceCollection> configServices,
        bool validateScopes = false)
    {
        var host = Host.CreateDefaultBuilder()
            .ConfigureWebHostDefaults(builder => builder
                .UseTestServer()
                .UseContentRoot(Directory.GetCurrentDirectory())
                .ConfigureServices(services => services.AddLogging())
                .ConfigureAppConfiguration((hostingContext, config) =>
                {
                    var env = hostingContext.HostingEnvironment;

                    config.AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
                          .AddJsonFile($"appsettings.{env.EnvironmentName}.json", optional: true, reloadOnChange: true);

                    if (env.IsDevelopment())
                    {
                        var appAssembly = Assembly.Load(new AssemblyName(env.ApplicationName));
                        if (appAssembly != null)
                        {
                            config.AddUserSecrets(appAssembly, optional: true);
                        }
                    }

                    config.AddEnvironmentVariables();
                })
                .UseStartup<TestStartup>()
                .ConfigureTestServices(services =>
                {
                    configServices(services);
                    services.AddLogging(x => x.AddDebug());
                }))
            .UseDefaultServiceProvider(options => options.ValidateScopes = validateScopes)
            .Build();

        host.StartAsync(TestContext.Current.CancellationToken).GetAwaiter().GetResult();
        return host;
    }

    private void UnobservedTaskExceptionHandler(IServiceProvider sp, UnobservedTaskExceptionEventArgs e)
    {
        var loggerFactory = sp.GetRequiredService<ILoggerFactory>();
        var logger = loggerFactory.CreateLogger("CronJobs");

        logger.LogError(e?.Exception, "Failed");

        // if not set exception is thrown from the tasks management context
        e?.SetObserved();
    }
}
