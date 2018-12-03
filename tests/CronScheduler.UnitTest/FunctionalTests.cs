using CronScheduler.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Internal;
using Moq;
using System;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace CronScheduler.UnitTest
{
    public class FunctionalTests
    {
        private readonly ITestOutputHelper output;

        public FunctionalTests(ITestOutputHelper output)
        {
            this.output = output;
        }

        [Fact]
        public async Task RunImmediately_Successfully()
        {
            var mockLogger = new Mock<ILogger<TestJob>>();

            var builder = new TestServer(
                    new WebHostBuilder()
                    .ConfigureTestServices(services =>
                    {

                        services.AddScheduler(ctx =>
                        {
                            ctx.Services.AddSingleton<IScheduledJob, TestJob>(_ => {
                                return new TestJob(mockLogger.Object)
                                {
                                    RunImmediately = true,
                                    CronSchedule = "* * * * *"
                                };
                            });
                        });

                        services.AddLogging();
                    })

                    .UseStartup<TestStartup>()
                );

            var client = builder.CreateClient();

            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();

            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLogger.Verify(l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<FormattedLogValues>(v => v.ToString().Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.IsAny<Func<object, Exception, string>>()
                ));
        }

        [Fact]
        public async Task RunDelayed_Successfully()
        {
            var mockLogger = new Mock<ILogger<TestJob>>();

            var builder = new TestServer(
                    new WebHostBuilder()
                    .ConfigureTestServices(services =>
                    {
                        services.AddScheduler(ctx =>
                        {
                            ctx.Services.AddSingleton<IScheduledJob, TestJob>(_ => {
                                return new TestJob(mockLogger.Object)
                                {
                                    RunImmediately = false,
                                    CronSchedule = "* * * * *"
                                };
                            });
                        });

                        services.AddLogging();
                    })

                    .UseStartup<TestStartup>()
                );

            var client = builder.CreateClient();
            await Task.Delay(TimeSpan.FromSeconds(65));

            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();

            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());

            mockLogger.Verify(l => l.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<FormattedLogValues>(v => v.ToString().Contains(nameof(TestJob))),
                It.IsAny<Exception>(),
                It.IsAny<Func<object, Exception, string>>()
                ));
        }

        [Fact]
        public async Task Run_And_Raise_UnobservedTaskException()
        {
            var mockLogger = new Mock<ILogger<TestJob>>();

            var builder = new TestServer(
                    new WebHostBuilder()
                    .ConfigureTestServices(services =>
                    {
                        services.AddScheduler(ctx =>
                        {
                            ctx.UnobservedTaskExceptionHandler = unobservedTaskExceptionHandler;
                            ctx.Services.AddSingleton<IScheduledJob, TestJob>(_ => {
                                return new TestJob(mockLogger.Object, true)
                                {
                                    RunImmediately = true,
                                    CronSchedule = "* * * * *"
                                };
                            });
                        });
                        services.AddLogging();
                    })

                    .UseStartup<TestStartup>()
                );

            var client = builder.CreateClient();

            var response = await client.GetAsync("/hc");
            response.EnsureSuccessStatusCode();

            Assert.Equal("healthy", await response.Content.ReadAsStringAsync());
        }

        private void unobservedTaskExceptionHandler(object sender, UnobservedTaskExceptionEventArgs e)
        {
            output.WriteLine(e.Exception.InnerException.Message);
            // if not set exception is thrown from the tasks management context
            e.SetObserved();
        }
    }
}
