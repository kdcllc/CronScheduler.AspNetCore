using CronScheduler.AspNetCore;

namespace CronScheduler
{
    public class TestJobOptions : SchedulerOptions
    {
        public string CustomField { get; set; }
    }
}
