using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;

namespace CronScheduler.UnitTest
{
    /// <summary>
    /// The purpose of this class to demonstrate how to utilize the same job
    /// with different schedules.
    /// </summary>
    public class TestJobDup : IScheduledJob
    {
        private readonly ILogger<TestJobDup> _logger;

        public TestJobDup(SchedulerOptions options, ILogger<TestJobDup> logger)
        {
            _logger = logger;
            Name = options.JobName;
        }

        public string Name { get; }

        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("Running {name}", nameof(TestJob));
            return Task.CompletedTask;
        }
    }
}
