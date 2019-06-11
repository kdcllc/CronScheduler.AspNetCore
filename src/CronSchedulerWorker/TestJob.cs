using System;
using System.Threading;
using System.Threading.Tasks;
using CronScheduler.AspNetCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CronScheduler
{
    public class TestJob : ScheduledJob
    {
        private readonly TestJobOptions _options;
        private readonly ILogger<TestJob> _logger;

        public TestJob(IOptionsMonitor<TestJobOptions> options, ILogger<TestJob> logger)
            : base(options.CurrentValue)
        {
            _options = options.CurrentValue;

            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public override async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation($"{nameof(TestJob)} is executing");

            await Task.CompletedTask;
        }
    }
}
