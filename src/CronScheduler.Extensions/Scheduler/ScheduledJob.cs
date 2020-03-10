using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.Extensions.Scheduler
{
    /// <inheritdoc/>
    [Obsolete("Use " + nameof(SchedulerOptions) + " with named job registration.")]
    public abstract class ScheduledJob : IScheduledJob
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="ScheduledJob"/> class.
        /// </summary>
        /// <param name="options"></param>
        protected ScheduledJob(SchedulerOptions options)
        {
            if (options == null)
            {
                throw new ArgumentNullException(nameof(options));
            }

            CronSchedule = options.CronSchedule;

            RunImmediately = options.RunImmediately;

            CronTimeZone = options?.CronTimeZone ?? string.Empty;
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
