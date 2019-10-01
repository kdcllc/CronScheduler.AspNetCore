using System;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

namespace Microsoft.Extensions.DependencyInjection
{
    public class SchedulerBuilder
    {
#pragma warning disable SA1401 // Fields should be private
#pragma warning disable CA1051 // Do not declare visible instance fields
        /// <summary>
        /// EventHanlder for Startup for Hosted Apps.
        /// </summary>
        public EventHandler<UnobservedTaskExceptionEventArgs> UnobservedTaskExceptionHandler;
#pragma warning restore CA1051 // Do not declare visible instance fields
#pragma warning restore SA1401 // Fields should be private

        public SchedulerBuilder(IServiceCollection services)
        {
            Services = services;
        }

        /// <summary>
        /// <see cref="IServiceCollection"/> for the DI.
        /// </summary>
        public IServiceCollection Services { get; }

        public IServiceCollection AddJob<TJob>()
            where TJob : class, IScheduledJob
        {
            Services.AddSingleton<IScheduledJob, TJob>();
            return Services;
        }

        public IServiceCollection AddJob<TJob>(Func<IServiceProvider, TJob> factory)
            where TJob : class, IScheduledJob
        {
            Services.AddSingleton(typeof(IScheduledJob), factory);

            return Services;
        }

        /// <summary>
        /// Adds <see cref="IScheduledJob"/> to DI.
        /// </summary>
        /// <typeparam name="TJob"></typeparam>
        /// <typeparam name="TJobOptions"></typeparam>
        /// <param name="sectionName"></param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob, TJobOptions>(string sectionName = "SchedulerJobs")
            where TJob : class, IScheduledJob
            where TJobOptions : SchedulerOptions, new()
        {
            Services.Configure<TJob, TJobOptions>(sectionName);

            AddJob<TJob>();

            return Services;
        }
    }
}
