using System;

namespace Microsoft.Extensions.Logging
{
#nullable disable
    internal static class LoggerExtensions
    {
        public static class EventIds
        {
            public static readonly EventId UnhandledException = new EventId(100, nameof(UnhandledException));
            public static readonly EventId JobNotRunning = new EventId(101, nameof(JobNotRunning));
            public static readonly EventId JobTimeZone = new EventId(102, nameof(JobTimeZone));
            public static readonly EventId JobTimeZoneFailedParsing = new EventId(103, nameof(JobTimeZoneFailedParsing));
        }

#pragma warning disable SA1201 // Elements should appear in the correct order
        private static readonly Action<ILogger, string, Exception> _unhandledException =
#pragma warning restore SA1201 // Elements should appear in the correct order
          LoggerMessage.Define<string>(
            LogLevel.Error,
            EventIds.UnhandledException,
            "An unhandled exception has occurred while executing custom task: {jobName}.");

        private static readonly Action<ILogger, string, string, Exception> _jobNotRunning =
        LoggerMessage.Define<string, string>(
            LogLevel.Warning,
            EventIds.JobNotRunning,
            "[Job][{jobName}] does not have CRON: {cron}. Task will not run.");

        private static readonly Action<ILogger, string, string, Exception> _jobTimeZone =
        LoggerMessage.Define<string, string>(
            LogLevel.Information,
            EventIds.JobTimeZone,
            "[Job][{jobName}] is running under time zone: {timeZone}");

        private static readonly Action<ILogger, string, string, string, Exception> _jobTimeZoneFailedParsing =
        LoggerMessage.Define<string, string, string>(
            LogLevel.Error,
            EventIds.JobTimeZoneFailedParsing,
            "[Job][{jobName}] tried parse {zone} but failed with {ex} running under local time zone");

        public static void UnhandledException(this ILogger logger, string jobName, Exception exception)
        {
            _unhandledException(logger, jobName, exception);
        }

        public static void MissingCron(this ILogger logger, string jobName, string cron)
        {
            _jobNotRunning(logger, jobName, cron, null);
        }

        public static void TimeZone(this ILogger logger, string jobName, string timeZone)
        {
            _jobTimeZone(logger, jobName, timeZone, null);
        }

        public static void TimeZoneParseFailure(this ILogger logger, string jobName, string cronTime, Exception ex)
        {
            _jobTimeZoneFailedParsing(logger, jobName, cronTime, ex.Message, null);
        }
    }
#nullable restore
}
