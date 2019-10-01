using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.BackgroundTask;

using Xunit;

namespace CronScheduler.UnitTest
{
    public class BackgroundQueueTests
    {
        [Fact]
        public async Task Dequeue_With_Successful_WorkItemName()
        {
            var workItemName = "TestItem";
            var context = new BackgroundTaskContext();

            var service = new BackgroundTaskQueue(context);

            service.QueueBackgroundWorkItem(
            async token =>
            {
                await Task.CompletedTask;
            },
            workItemName);

            var task = await service.DequeueAsync(CancellationToken.None);

            await task.workItem(CancellationToken.None);

            Assert.Equal(workItemName, task.workItemName);

            service.Dispose();
        }
    }
}
