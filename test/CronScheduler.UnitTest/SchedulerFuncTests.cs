using System;
using System.IO;
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
using Xunit.Abstractions;

using Range = Moq.Range;

namespace CronScheduler.UnitTest
{
    public class SchedulerFuncTests
    {
        private readonly ITestOutputHelper _output;

        public SchedulerFuncTests(ITestOutputHelper output)
        {
            _output = output;
        }

        [Fact]
        public async Task Job_RunImmediately_Factory_Successfully()
        {
            // assign
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

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(6));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLoggerTestJob.Verify(
                l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((object v, Type _) => v.ToString() !.Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.Is<Func<object, Exception, string>>((v, t) => true)),
                Times.Between(1, 2, Range.Inclusive));
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

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(6));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLoggerTestJob.Verify(
                    l => l.Log(
                    LogLevel.Information,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((object v, Type _) => v.ToString() !.Contains(nameof(TestJob))),
                    It.IsAny<Exception>(),
                    It.Is<Func<object, Exception, string>>((v, t) => true)),
                    Times.Between(2, 6, Range.Inclusive));
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

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(6));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLoggerTestJob.Verify(
                    l => l.Log(
                    LogLevel.Information,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((object v, Type _) => v.ToString() !.Contains(nameof(TestJob))),
                    It.IsAny<Exception>(),
                    It.Is<Func<object, Exception, string>>((v, t) => true)),
                    Times.Between(1, 2, Range.Inclusive));
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

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(6));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            // fixed moq and log according to https://github.com/moq/moq4/issues/918#issuecomment-535060645
            mockLogger.Verify(
                l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((object v, Type _) => v.ToString() !.Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.Is<Func<object, Exception, string>>((v, t) => true)),
                Times.Between(1, 2, Range.Inclusive));
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

                    ctx.UnobservedTaskExceptionHandler = UnobservedTaskExceptionHandler;

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

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(6));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLogger.Verify(
                l => l.Log(
                        LogLevel.Error,
                        It.IsAny<EventId>(),
                        It.Is<It.IsAnyType>((object v, Type _) => v.ToString() !.Contains(nameof(Exception))),
                        It.IsAny<Exception>(),
                        It.Is<Func<object, Exception, string>>((v, t) => true)),
                Times.Between(1, 2, Range.Inclusive));
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

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(3));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLogger.Verify(
                l => l.Log(
                        LogLevel.Error,
                        It.IsAny<EventId>(),
                        It.Is<It.IsAnyType>((object v, Type _) => v.ToString() !.Contains(nameof(Exception))),
                        It.IsAny<Exception>(),
                        It.Is<Func<object, Exception, string>>((v, t) => true)),
                Times.Between(1, 4, Range.Inclusive));
        }

        private IWebHostBuilder CreateHost(
            Action<IServiceCollection> configServices,
            bool validateScopes = false)
        {
            return new WebHostBuilder()
                .UseContentRoot(Directory.GetCurrentDirectory())
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
                    services.AddLogging();
                })
                .UseDefaultServiceProvider(options => options.ValidateScopes = validateScopes);
        }

        private void UnobservedTaskExceptionHandler(object sender, UnobservedTaskExceptionEventArgs e)
        {
            _output.WriteLine(e.Exception?.InnerException?.Message);

            // if not set exception is thrown from the tasks management context
            e.SetObserved();
        }
    }
}
