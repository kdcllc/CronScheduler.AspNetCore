using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;

namespace CronSchedulerApp.Jobs
{
    public class TestJob : IScheduledJob
    {
        private readonly ILogger<TestJob> _logger;
        private SchedulerOptions _options;

        public TestJob(
            SchedulerOptions options,
            ILogger<TestJob> logger)
        {
            _options = options;
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public string Name { get; } = nameof(TestJob);

        // will be removed in the next release
        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("{cronSchedule} - {id}", _options.CronSchedule, Guid.NewGuid());

            return Task.CompletedTask;
        }
    }
}
