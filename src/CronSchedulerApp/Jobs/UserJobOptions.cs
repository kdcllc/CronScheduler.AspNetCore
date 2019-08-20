using CronScheduler.AspNetCore;

namespace CronSchedulerApp.Jobs
{
    public class UserJobOptions : SchedulerOptions
    {
        public string ClaimName { get; set; }
    }
}
