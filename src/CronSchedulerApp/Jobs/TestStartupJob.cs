using CronScheduler.AspNetCore;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronSchedulerApp
{
    public class TestStartupJob : IStartupJob
    {
        private readonly ILogger<TestStartupJob> _logger;

        public TestStartupJob(ILogger<TestStartupJob> logger)
        {
            _logger = logger;
        }

        public async Task ExecuteAsync(CancellationToken cancellationToken = default)
        {
            _logger.LogInformation("{job} started", nameof(TestStartupJob));

            await Task.Delay(TimeSpan.FromSeconds(10));

            _logger.LogInformation("{job} ended", nameof(TestStartupJob));
        }
    }
}
