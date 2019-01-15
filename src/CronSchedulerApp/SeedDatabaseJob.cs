using CronScheduler.AspNetCore;
using CronSchedulerApp.Data;
using System;
using System.Threading.Tasks;

namespace CronSchedulerApp
{
    public class SeedDatabaseJob : IStartupJob
    {
        private readonly ApplicationDbContext _dbContext;

        public SeedDatabaseJob(ApplicationDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task StartAsync()
        {
            // await for docker container to come up.
            await Task.Delay(TimeSpan.FromSeconds(40));
            await _dbContext.Database.EnsureCreatedAsync();
        }
    }
}
