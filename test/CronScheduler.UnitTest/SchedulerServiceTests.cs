using System;
using System.Collections.Generic;
using System.Linq;

using Bet.Extensions.Testing.Logging;

using CronScheduler.Extensions.Internal;
using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

using Xunit;
using Xunit.Abstractions;

namespace CronScheduler.UnitTest
{
    public class SchedulerServiceTests
    {
        private readonly ITestOutputHelper _output;

        public SchedulerServiceTests(ITestOutputHelper output)
        {
            _output = output ?? throw new ArgumentNullException(nameof(output));
        }

        [Fact]
        public void Add_Job_Successfully()
        {
            var dic = new Dictionary<string, string>
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

            service.AddOptions<SchedulerOptions>(name)
                .Configure<IConfiguration>((options, configuration) =>
                {
                    configuration.Bind("SchedulerJobs:TestJobException", options);
                });

            service.AddLogging(builder =>
            {
                builder.AddConsole();
                builder.AddDebug();
                builder.AddXunit(_output, LogLevel.Debug);
            });

            service.AddSingleton<SchedulerRegistration>();

            var sp = service.BuildServiceProvider();

            var instance = sp.GetService<SchedulerRegistration>();

            using var logFactory = TestLoggerBuilder.Create(builder =>
            {
                builder.AddConsole();
                builder.AddDebug();
                builder.AddXunit(_output, LogLevel.Debug);
            });

            var job = new TestJob(logFactory.CreateLogger<TestJob>());
            var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(name);

            instance.AddOrUpdate(job.GetType().Name, job, options);

            Assert.Single(instance.Jobs);
        }

        [Fact]
        public void Add_Job_Successfully_1()
        {
            var dic = new Dictionary<string, string>
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
                builder.AddXunit(_output, LogLevel.Debug);
            });

            service.AddSingleton<SchedulerRegistration>();

            var sp = service.BuildServiceProvider();

            var instance = sp.GetService<SchedulerRegistration>();

            using var logFactory = TestLoggerBuilder.Create(builder =>
            {
                builder.AddConsole();
                builder.AddDebug();
                builder.AddXunit(_output, LogLevel.Debug);
            });

            var job = new TestJob(logFactory.CreateLogger<TestJob>());
            var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(name);

            instance.AddOrUpdate(job.GetType().Name, job, options);

            Assert.Equal(1, instance.Jobs.Count);

            configuration.Providers.ToList()[0].Set("SchedulerJobs:TestJobException:CronSchedule", "*/1 * * * * *");
            configuration.Reload();

            _output.WriteLine(instance.Jobs.ToArray()[0].Value.Schedule.ToString());
        }
    }
}
