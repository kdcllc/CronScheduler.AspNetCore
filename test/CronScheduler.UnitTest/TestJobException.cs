using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CronScheduler.UnitTest
{
    public class TestJobExceptionOptions : SchedulerOptions
    {
        public bool RaiseException { get; set; }
    }

    public class TestJobException : IScheduledJob
    {
        private readonly ILogger<TestJobException> _logger;
        private readonly TestJobExceptionOptions _options;

        public TestJobException(
            ILogger<TestJobException> logger,
            IOptionsMonitor<TestJobExceptionOptions> optionsMonitor)
        {
            _logger = logger;

            _options = optionsMonitor.Get(Name);
        }

        public string Name { get; } = nameof(TestJobException);

        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            if (_options.RaiseException)
            {
                var message = nameof(Exception);
                _logger.LogError(message);
                throw new Exception(message);
            }

            _logger.LogInformation("Running {name}", nameof(TestJobException));
            return Task.CompletedTask;
        }
    }
}
