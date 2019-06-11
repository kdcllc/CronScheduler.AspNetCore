using Cronos;
using System;

namespace CronScheduler.AspNetCore
{
    internal class SchedulerTaskWrapper
    {
        public CronExpression Schedule { get; set; }
        public IScheduledJob ScheduledJob { get; set; }

        public DateTime LastRunTime { get; set; }
        public DateTime NextRunTime { get; set; }

        public SchedulerTaskWrapper(
            CronExpression cronExpression,
            IScheduledJob scheduledJob,
            DateTime nextRunTime)
        {
            Schedule = cronExpression;
            ScheduledJob = scheduledJob;
            NextRunTime = nextRunTime;
        }

        public void Increment()
        {
            LastRunTime = NextRunTime;
            NextRunTime = Schedule.GetNextOccurrence(NextRunTime).Value;
        }

        public bool ShouldRun(DateTime currentTime)
        {
            return NextRunTime < currentTime && LastRunTime != NextRunTime;
        }
    }
}
