using CronScheduler.Extensions.Scheduler;

namespace CronScheduler
{
    public class TestJobOptions : SchedulerOptions
    {
        public string CustomField { get; set; }
    }
}
