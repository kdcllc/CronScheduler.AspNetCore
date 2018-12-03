using CronScheduler.AspNetCore;
using Microsoft.Extensions.Logging;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.UnitTest
{
    public class TestJob : IScheduledJob
    {
        private readonly ILogger<TestJob> _logger;

        public TestJob(ILogger<TestJob> logger)
        {
            _logger = logger;
        }

        public string CronSchedule { get; set; }

        public bool RunImmediately { get; set; }

        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("Running {name}", nameof(TestJob));
            return Task.CompletedTask;
        }
    }
}
