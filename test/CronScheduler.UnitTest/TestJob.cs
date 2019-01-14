using CronScheduler.AspNetCore;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.UnitTest
{
    public class TestJob : IScheduledJob
    {
        private readonly ILogger<TestJob> _logger;
        private readonly bool _raiseException;

        public TestJob(
            ILogger<TestJob> logger,
            bool raiseException = false)
        {
            _logger = logger;
            _raiseException = raiseException;
        }

        public string CronSchedule { get; set; }

        public bool RunImmediately { get; set; }

        public string CronTimeZone { get; set; }

        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            if (_raiseException)
            {
                var message = "Unhandle Exception";
                _logger.LogError(message);
                throw new Exception(message);
            }
            _logger.LogInformation("Running {name}", nameof(TestJob));
            return Task.CompletedTask;
        }
    }
}
