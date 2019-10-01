using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;

namespace CronScheduler.UnitTest
{
    public class TestJob : IScheduledJob
    {
        private readonly ILogger<TestJob> _logger;

        public TestJob(
            ILogger<TestJob> logger)
        {
            _logger = logger;
        }

        public string CronSchedule { get; set; }

        public bool RunImmediately { get; set; }

        public string CronTimeZone { get; set; }

        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("Running {name}", nameof(TestJob));
            return Task.CompletedTask;
        }
    }

    public class TestJobExceptionOptions : SchedulerOptions
    {
        public bool RaiseException { get; set; }
    }

    public class TestJobException : IScheduledJob
    {
        private readonly ILogger<TestJobException> _logger;
        private readonly bool _raiseException;

        public TestJobException(
            ILogger<TestJobException> logger,
            TestJobExceptionOptions jobOptions,
            bool raiseException = false)
        {
            _logger = logger;
            _raiseException = raiseException;

            if (jobOptions != null)
            {
                _raiseException = jobOptions.RaiseException;
                CronSchedule = jobOptions.CronSchedule;
                RunImmediately = jobOptions.RunImmediately;
                CronTimeZone = jobOptions.CronTimeZone;
            }
        }

        public string CronSchedule { get; set; }

        public bool RunImmediately { get; set; }

        public string CronTimeZone { get; set; }

        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            if (_raiseException)
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
