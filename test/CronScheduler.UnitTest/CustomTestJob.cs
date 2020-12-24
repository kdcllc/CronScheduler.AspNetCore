using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;

namespace CronScheduler.UnitTest
{
    public class CustomTestJob : IScheduledJob
    {
        private readonly CustomTestJobOptions _options;
        private readonly ILogger<CustomTestJob> _logger;

        public CustomTestJob(CustomTestJobOptions options, ILogger<CustomTestJob> logger)
        {
            _options = options;
            _logger = logger;
            Name = options.JobName;
        }

        public string Name { get; }

        public Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("Running {name}", nameof(CustomTestJob));
            _logger.LogInformation(_options.DisplayText);

            return Task.CompletedTask;
        }
    }
}
