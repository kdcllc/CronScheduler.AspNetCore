using System.Threading;
using System.Threading.Tasks;

using CronScheduler.AspNetCore;

using CronSchedulerApp.Data;

using Microsoft.Extensions.Logging;

namespace CronSchedulerApp.Jobs.Startup
{
    public class SeedDatabaseStartupJob : IStartupJob
    {
        private readonly ApplicationDbContext _dbContext;
        private readonly ILogger<SeedDatabaseStartupJob> _logger;

        public SeedDatabaseStartupJob(
            ApplicationDbContext dbContext,
            ILogger<SeedDatabaseStartupJob> logger)
        {
            _dbContext = dbContext;
            _logger = logger;
        }

        public async Task ExecuteAsync(CancellationToken cancellationToken = default)
        {
            _logger.LogInformation("{job} started.", nameof(SeedDatabaseStartupJob));

            // await for docker container to come up.
            // await Task.Delay(TimeSpan.FromSeconds(40));
            await _dbContext.Database.EnsureCreatedAsync(cancellationToken);
            _logger.LogInformation("{job} ended.", nameof(SeedDatabaseStartupJob));
        }
    }
}
