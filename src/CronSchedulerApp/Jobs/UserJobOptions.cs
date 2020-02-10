using CronScheduler.Extensions.Scheduler;

namespace CronSchedulerApp.Jobs
{
    public class UserJobOptions : SchedulerOptions
    {
        public string ClaimName { get; set; } = string.Empty;
    }
}
