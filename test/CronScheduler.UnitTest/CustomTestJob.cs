using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;

namespace CronScheduler.UnitTest;

public class CustomTestJob(
    CustomTestJobOptions options,
    ILogger<CustomTestJob> logger) : IScheduledJob
{
    public string Name { get; } = options.JobName;

    public Task ExecuteAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("Running {name}", nameof(CustomTestJob));
        logger.LogInformation(options.DisplayText);

        return Task.CompletedTask;
    }
}
