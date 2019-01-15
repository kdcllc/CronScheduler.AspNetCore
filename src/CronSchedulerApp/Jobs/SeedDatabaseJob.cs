using CronScheduler.AspNetCore;
using CronSchedulerApp.Data;
using Microsoft.Extensions.Logging;
using System.Threading.Tasks;

namespace CronSchedulerApp
{
    public class SeedDatabaseJob : IStartupJob
    {
        private readonly ApplicationDbContext _dbContext;
        private readonly ILogger<SeedDatabaseJob> _logger;

        public SeedDatabaseJob(
            ApplicationDbContext dbContext,
            ILogger<SeedDatabaseJob> logger)
        {
            _dbContext = dbContext;
            _logger = logger;
        }

        public async Task StartAsync()
        {
            _logger.LogInformation("{job} started.", nameof(SeedDatabaseJob));
            // await for docker container to come up.
            // await Task.Delay(TimeSpan.FromSeconds(40));

            await _dbContext.Database.EnsureCreatedAsync();
            _logger.LogInformation("{job} ended.", nameof(SeedDatabaseJob));
        }
    }
}
