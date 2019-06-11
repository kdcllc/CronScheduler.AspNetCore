using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    /// <inheritdoc/>
    public abstract class ScheduledJob : IScheduledJob
    {
        /// <inheritdoc/>
        public string CronSchedule { get; }

        /// <inheritdoc/>
        public bool RunImmediately { get; }

        /// <inheritdoc/>
        public string CronTimeZone { get; }

        public ScheduledJob(SchedulerOptions options)
        {
            if (options == null)
            {
                throw new ArgumentNullException(nameof(options));
            }

            CronSchedule = options.CronSchedule;

            RunImmediately = options.RunImmediately;

            CronTimeZone = options.CronTimeZone;
        }

        /// <inheritdoc/>
        public abstract Task ExecuteAsync(CancellationToken cancellationToken);
    }
}
