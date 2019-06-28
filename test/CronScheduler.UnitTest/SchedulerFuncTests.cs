using CronScheduler.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Internal;
using Moq;
using System;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace CronScheduler.UnitTest
{
    public class SchedulerFuncTests
    {
        private readonly ITestOutputHelper output;

        public SchedulerFuncTests(ITestOutputHelper output)
        {
            this.output = output;
        }

        [Fact(Skip = "Review")]
        public async Task RunImmediately_Successfully()
        {
            // assign
            var mockLoggerTestJob = new Mock<ILogger<TestJob>>();
            var mockLoggerTestJobException = new Mock<ILogger<TestJobException>>();

            var host = CreateHost(services =>
            {
                services.AddScheduler(ctx =>
                {
                    ctx.AddJob<TestJob>(_ =>
                    {
                        return new TestJob(mockLoggerTestJob.Object)
                        {
                            RunImmediately = true,
                            CronSchedule = "*/10 * * * * *"
                        };
                    });

                    services.AddTransient<ILogger<TestJobException>>(x => mockLoggerTestJobException.Object);
                    ctx.AddJob<TestJobException, TestJobExceptionOptions>();
                });
            });

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(6));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLoggerTestJob.Verify(l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<FormattedLogValues>(v => v.ToString().Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.IsAny<Func<object, Exception, string>>()
                ),
                Times.Between(1,2,Range.Inclusive));

            mockLoggerTestJobException.Verify(l => l.Log(
                      LogLevel.Error,
                      It.IsAny<EventId>(),
                      It.Is<FormattedLogValues>(v => v.ToString().Contains(nameof(Exception))),
                      It.IsAny<Exception>(),
                      It.IsAny<Func<object, Exception, string>>()
                      ),
                     Times.Between(1, 2, Range.Inclusive));
        }

        [Fact]
        public async Task RunDelayed_Successfully()
        {
            var mockLogger = new Mock<ILogger<TestJob>>();

            var host = CreateHost(services =>
            {
                services.AddScheduler(ctx =>
                {
                    ctx.Services.AddSingleton<IScheduledJob, TestJob>(_ => {
                        return new TestJob(mockLogger.Object)
                        {
                            RunImmediately = false,
                            CronSchedule = "*/05 * * * * *"
                        };
                    });
                });
            });

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(15));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLogger.Verify(l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<FormattedLogValues>(v => v.ToString().Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.IsAny<Func<object, Exception, string>>()
                ),
                Times.Between(1,3,Range.Inclusive));
        }

        [Fact]
        public async Task Run_And_Raise_UnobservedTaskException()
        {
            // arrange
            var mockLogger = new Mock<ILogger<TestJobException>>();

            var host = CreateHost(services =>
            {
                services.AddScheduler(ctx =>
                {
                    ctx.UnobservedTaskExceptionHandler = unobservedTaskExceptionHandler;
                    ctx.AddJob<TestJobException>(_ =>
                    {
                        return new TestJobException(mockLogger.Object, null, true)
                        {
                            RunImmediately = true,
                            CronSchedule = "*/10 * * * * *"
                        };
                    });
                });

                // services.AddTransient<ILogger<TestJob>>(x => mockLogger.Object);

                // short registration without UnobservedTaskExceptionHandler
                //services.AddSchedulerJob<TestJob,TestJobOptions>();
            });

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(5));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLogger.Verify(l => l.Log(
                        LogLevel.Error,
                        It.IsAny<EventId>(),
                        It.Is<FormattedLogValues>(v => v.ToString().Contains(nameof(Exception))),
                        It.IsAny<Exception>(),
                        It.IsAny<Func<object, Exception, string>>()
                        ),
                        Times.Between(1, 2, Range.Inclusive));
        }

        [Fact(Skip = "Review")]
        public async Task Run_Job_With_Options_And_Raise_Exception()
        {
            // arrange
            var mockLogger = new Mock<ILogger<TestJobException>>();

            var host = CreateHost(services =>
            {
                // used for tests
                services.AddTransient<ILogger<TestJobException>>(x => mockLogger.Object);
                // short registration without UnobservedTaskExceptionHandler
                services.AddSchedulerJob<TestJobException, TestJobExceptionOptions>();
            });

            var client = new TestServer(host).CreateClient();

            // act
            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(5));

            // assert
            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLogger.Verify(l => l.Log(
                        LogLevel.Error,
                        It.IsAny<EventId>(),
                        It.Is<FormattedLogValues>(v => v.ToString().Contains(nameof(Exception))),
                        It.IsAny<Exception>(),
                        It.IsAny<Func<object, Exception, string>>()
                        ),
                        Times.Between(1,2,Range.Inclusive));
        }

        private IWebHostBuilder CreateHost(
            Action<IServiceCollection> configServices,
            bool validateScopes = false)
        {
            return new WebHostBuilder()
                .UseContentRoot(Directory.GetCurrentDirectory())
                .ConfigureAppConfiguration((hostingContext, config)=>
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

        private void unobservedTaskExceptionHandler(object sender, UnobservedTaskExceptionEventArgs e)
        {
            output.WriteLine(e.Exception.InnerException.Message);
            // if not set exception is thrown from the tasks management context
            e.SetObserved();
        }
    }
}
