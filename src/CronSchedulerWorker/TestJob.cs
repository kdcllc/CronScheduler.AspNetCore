using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CronSchedulerWorker
{
    public class TestJob : ScheduledJob
    {
        private readonly TestJobOptions _options;
        private readonly ILogger<TestJob> _logger;

        public TestJob(IOptionsMonitor<TestJobOptions> options, ILogger<TestJob> logger, IHostLifetime lifetime)
            : base(options.CurrentValue)
        {
            _options = options.CurrentValue;

            _logger = logger ?? throw new ArgumentNullException(nameof(logger));

            // _logger.LogInformation("IsSystemd: {isSystemd}", lifetime.GetType() == typeof(SystemdLifetime));
            _logger.LogInformation("IHostLifetime: {hostLifetime}", lifetime.GetType());
        }

        public override async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("{jobName} is executing with Custom Field Value: {customField}", nameof(TestJob), _options.CustomField);

            await Task.CompletedTask;
        }
    }
}
