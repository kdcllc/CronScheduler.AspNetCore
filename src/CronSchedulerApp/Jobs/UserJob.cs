using System;
using System.Security.Claims;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using CronSchedulerApp.Services;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace CronSchedulerApp.Jobs
{
    public class UserJob : ScheduledJob
    {
        private readonly UserJobOptions _options;
        private readonly IServiceProvider _provider;

        public UserJob(
            IServiceProvider provider,
            IOptionsMonitor<UserJobOptions> options) : base(options.CurrentValue)
        {
            _options = options.CurrentValue;
            _provider = provider ?? throw new ArgumentNullException(nameof(provider));
        }

        public override async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            // https://docs.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services?view=aspnetcore-2.2&tabs=visual-studio#consuming-a-scoped-service-in-a-background-task
            using (var scope = _provider.CreateScope())
            {
                var userService = scope.ServiceProvider.GetRequiredService<UserService>();

                var users = userService.GetUsers();

                foreach (var user in users)
                {
                    await userService.AddClaimAsync(user, new Claim(_options.ClaimName, DateTime.UtcNow.ToString()));
                }
            }
        }
    }
}
