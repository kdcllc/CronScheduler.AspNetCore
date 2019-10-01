using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    /// <inheritdoc/>
    public abstract class ScheduledJob : IScheduledJob
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="ScheduledJob"/> class.
        /// </summary>
        /// <param name="options"></param>
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
        public string CronSchedule { get; }

        /// <inheritdoc/>
        public bool RunImmediately { get; }

        /// <inheritdoc/>
        public string CronTimeZone { get; }

        /// <inheritdoc/>
        public abstract Task ExecuteAsync(CancellationToken cancellationToken);
    }
}
