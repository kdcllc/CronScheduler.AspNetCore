using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;

namespace CronSchedulerApp.Jobs
{
    public class TestJob : IScheduledJob
    {
        private SchedulerOptions _options;
        private readonly ILogger<TestJob> _logger;

        public TestJob(SchedulerOptions options, ILogger<TestJob> logger)
        {
            _options = options;
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        // will be removed in the next release
        public string CronSchedule { get; }

        // will be removed in the next release
        public string CronTimeZone { get; }

        // will be removed in the next release
        public bool RunImmediately { get; }

        // will be removed in the next release
        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("{cronSchedule} - {id}", _options.CronSchedule, Guid.NewGuid());

            return Task.CompletedTask;
        }
    }
}
