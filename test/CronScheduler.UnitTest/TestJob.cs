using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;

namespace CronScheduler.UnitTest;

public class TestJob : IScheduledJob
{
    private readonly ILogger<TestJob> _logger;

    public TestJob(ILogger<TestJob> logger)
    {
        _logger = logger;
    }

    public string Name { get; } = nameof(TestJob);

    public Task ExecuteAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Running {name}", nameof(TestJob));
        return Task.CompletedTask;
    }
}
