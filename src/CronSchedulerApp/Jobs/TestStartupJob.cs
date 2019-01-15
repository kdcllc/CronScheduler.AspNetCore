using CronScheduler.AspNetCore;
using Microsoft.Extensions.Logging;
using System;
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

        public async Task StartAsync()
        {
            _logger.LogInformation("{job} started", nameof(TestStartupJob));

            await Task.Delay(TimeSpan.FromSeconds(5));

            _logger.LogInformation("{job} ended", nameof(TestStartupJob));
        }
    }
}
