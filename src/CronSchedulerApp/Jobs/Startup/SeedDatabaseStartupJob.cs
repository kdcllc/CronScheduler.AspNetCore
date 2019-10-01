using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.StartupInitializer;

using CronSchedulerApp.Data;

using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Logging;

namespace CronSchedulerApp.Jobs.Startup
{
    /// <summary>
    /// This jobs demonstrates how to use EF context to seed the database before any request being served.
    /// It ensures that DB exists and creates 5 users.
    /// </summary>
    public class SeedDatabaseStartupJob : IStartupJob
    {
        private readonly ApplicationDbContext _dbContext;
        private readonly ILogger<SeedDatabaseStartupJob> _logger;
        private readonly UserManager<IdentityUser> _userManager;

        public SeedDatabaseStartupJob(
            ApplicationDbContext dbContext,
            UserManager<IdentityUser> userManager,
            ILogger<SeedDatabaseStartupJob> logger)
        {
            _dbContext = dbContext ?? throw new System.ArgumentNullException(nameof(dbContext));
            _logger = logger ?? throw new System.ArgumentNullException(nameof(logger));
            _userManager = userManager ?? throw new System.ArgumentNullException(nameof(userManager));
        }

        public async Task ExecuteAsync(CancellationToken cancellationToken = default)
        {
            _logger.LogInformation("{job} started.", nameof(SeedDatabaseStartupJob));

            // await for docker container to come up.
            // await Task.Delay(TimeSpan.FromSeconds(40));
            await _dbContext.Database.EnsureCreatedAsync(cancellationToken);

            for (var i = 0; i < 5; i++)
            {
                var user = $"demo{i}@kingdavidconsulting.com";

                var defaultUser = new IdentityUser
                {
                    UserName = user,
                    Email = user,
                    EmailConfirmed = true
                };

                await _userManager.CreateAsync(defaultUser, $"P@ss@word{i}");
            }

            _logger.LogInformation("{job} ended.", nameof(SeedDatabaseStartupJob));
        }
    }
}
