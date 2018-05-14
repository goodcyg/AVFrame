//
//  main.m
//  avframe
//
//  Created by Jackson on 2017/6/15.
//  Copyright © 2017年 Jackson. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "HYFileManager.h"

#ifdef __cplusplus
extern "C" {
#endif

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libavutil/avutil.h>
#import <libavutil/imgutils.h>
#import <libswscale/swscale.h>
#import <libswresample/swresample.h>
#import <jpeglib.h>

#ifdef __cplusplus
}
#endif


void SavePPM(AVFrame *pFrame, int width, int height, int iFrame)
{
    FILE *pFile;

    int  y;
    
    // Open file
    
    const char *filename=[NSString stringWithFormat:@"%@/frame%d.ppm",[HYFileManager documentsDir],iFrame].UTF8String;
    pFile=fopen(filename, "wb");
    if(pFile==NULL)
        return;
    // Write header
    fprintf(pFile, "P6\n%d %d\n255\n", width, height);
    // Write pixel data
    for(y=0; y<height; y++)
        fwrite(pFrame->data[0]+y*pFrame->linesize[0], 1, width*3, pFile);
    // Close file  
    fclose(pFile);  
}
void saveJPG(AVFrame* pFrame, int width, int height, int iFrame,int64_t time)
{
    struct jpeg_compress_struct cinfo;
    struct jpeg_error_mgr jerr;
    JSAMPROW row_pointer[1];
    int row_stride;
    uint8_t *buffer;
    FILE *fp;
    
    buffer = pFrame->data[0];
    
   
    const char *filename=[NSString stringWithFormat:@"%@/%d_%lld_%lld.jpg",[HYFileManager documentsDir],iFrame,pFrame->pts,time].UTF8String;
    
    fp = fopen(filename, "wb");
    
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_compress(&cinfo);
    jpeg_stdio_dest(&cinfo, fp);
    
    cinfo.image_width = width;
    cinfo.image_height = height;
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    
    jpeg_set_defaults(&cinfo);
    
    jpeg_set_quality(&cinfo, 80, TRUE);
    
    jpeg_start_compress(&cinfo, TRUE);
    
    row_stride = width * 3;
    while (cinfo.next_scanline < height)
    {
        row_pointer[0] = &buffer[cinfo.next_scanline * row_stride];
        (void)jpeg_write_scanlines(&cinfo, row_pointer, 1);
    }
    
    jpeg_finish_compress(&cinfo);
    fclose(fp);
    jpeg_destroy_compress(&cinfo);
    return;
}

//enum AVPictureType {
//    AV_PICTURE_TYPE_NONE = 0, ///< Undefined
//    AV_PICTURE_TYPE_I,     ///< Intra
//    AV_PICTURE_TYPE_P,     ///< Predicted
//    AV_PICTURE_TYPE_B,     ///< Bi-dir predicted
//    AV_PICTURE_TYPE_S,     ///< S(GMC)-VOP MPEG-4
//    AV_PICTURE_TYPE_SI,    ///< Switching Intra
//    AV_PICTURE_TYPE_SP,    ///< Switching Predicted
//    AV_PICTURE_TYPE_BI,    ///< BI type
//};


char *getFrameType(enum AVPictureType pict_type)
{
    switch (pict_type) {
        case AV_PICTURE_TYPE_NONE:
            return "N";
        case AV_PICTURE_TYPE_I:
            return "I";
        case AV_PICTURE_TYPE_P:
          return "P";
        case AV_PICTURE_TYPE_B:
          return "B";
        case AV_PICTURE_TYPE_S:
         return "S";
            
        case AV_PICTURE_TYPE_SI:
          return "SI";
        case AV_PICTURE_TYPE_SP:
          return "SP";
        case AV_PICTURE_TYPE_BI:
           return "BI";
            
         default:
          return "";
    }
    return "";
}
#pragma mark - 音视频真正解码的地方
static int decode(AVCodecContext *avctx, AVFrame *frame, int *got_frame, AVPacket *pkt)
{
    int ret;
    
    *got_frame = 0;
    
    if (pkt)
    {
        //ffmpeg内部会缓冲几帧，要想取出来就需要传递空的AVPacket进去
        ret = avcodec_send_packet(avctx, pkt);
        // In particular, we don't expect AVERROR(EAGAIN), because we read all
        // decoded frames with avcodec_receive_frame() until done.
        if (ret < 0 && ret != AVERROR_EOF)
        {
            return ret;
        }
    }
    
    //可以多次调用
    ret = avcodec_receive_frame(avctx, frame);
    printf("pkt->dts:%d pkt->pts:%d frame->dts:%d frame->pts:%d",pkt?pkt->dts:0,pkt?pkt->pts:0,frame->pkt_dts,frame->pts);
    if (ret < 0 && ret != AVERROR(EAGAIN))
    {
        return ret;
    }
    if (ret >= 0)
    {
        *got_frame = 1;
    }
    
    return 0;
}
#if 0
int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
#else

int main(int argc, char *argv[])
{
    AVFormatContext *pFormatCtx;
    struct SwsContext *pSwsCtx;
    int i,j;
    int   videoStream_index=-1;
    int   audioStream_index=-1;
    AVCodecContext  *pCodecContext;
    AVCodec         *pCodec;
    AVFrame         *pFrame;
    AVFrame         *pFrameRGB;
    AVPacket        packet;
    int             numBytes;
    uint8_t         *buffer;
    __unused int frameFinished;

    int64_t nb_frames=0;
    int64_t nb_frames_audio=0;
    NSString *mp4=[[HYFileManager documentsDir] stringByAppendingPathComponent:@"20184k.m4v"];
//    NSString *mp4=[[HYFileManager documentsDir] stringByAppendingPathComponent:@"tmp.mp4"];
   const char *filename=mp4.UTF8String;
    printf("please input a filename:%s \n",filename);

    
    // Register all formats and codecs
    av_register_all();
    
    avformat_network_init();
    // Open video file
    pFormatCtx=avformat_alloc_context();
      AVInputFormat* iformat=av_find_input_format("h264");
    
    if(avformat_open_input(&pFormatCtx,filename, NULL,NULL)!=0)
        return -1; // Couldn't open file
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx,0)<0)
        return -1; // Couldn't find stream information
    // Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, filename, false);
    // Find the first video stream
    for(i=0; i<pFormatCtx->nb_streams; i++)
    {
       if(pFormatCtx->streams[i]->codecpar->codec_type==AVMEDIA_TYPE_VIDEO)
        {
            videoStream_index=i;
            nb_frames=pFormatCtx->streams[i]->nb_frames;
            printf("video fps:%0.2f fps2:%0.2f time:%0.fms Video duration:%lld  duration:%lld \n",pFormatCtx->streams[i]->avg_frame_rate.num/(double)pFormatCtx->streams[i]->avg_frame_rate.den,av_q2d(pFormatCtx->streams[i]->r_frame_rate),nb_frames/(pFormatCtx->streams[i]->avg_frame_rate.num/(double)pFormatCtx->streams[i]->avg_frame_rate.den)*1000,pFormatCtx->streams[i]->duration,pFormatCtx->duration);
            continue;
        }
        
        if(pFormatCtx->streams[i]->codecpar->codec_type==AVMEDIA_TYPE_AUDIO)
        {
            AVStream *audio=pFormatCtx->streams[i];
            audioStream_index=i;
            nb_frames_audio=pFormatCtx->streams[i]->nb_frames;
            
            printf("audio fps:%0.2f fps2:%0.2f time:%0.fms Video duration:%lld  duration:%lld \n",pFormatCtx->streams[i]->avg_frame_rate.num/(double)pFormatCtx->streams[i]->avg_frame_rate.den,av_q2d(pFormatCtx->streams[i]->r_frame_rate),nb_frames_audio/(pFormatCtx->streams[i]->avg_frame_rate.num/(double)pFormatCtx->streams[i]->avg_frame_rate.den)*1000,pFormatCtx->streams[i]->duration,pFormatCtx->duration);
            continue;
        }
    }
    if(videoStream_index==-1||audioStream_index==-1)
        return -1; // Didn't find a video stream
    // Get a pointer to the codec context for the video stream
    //pCodecContext=pFormatCtx->streams[videoStream_index]->codec;
    
    // Find the decoder for the video stream
    pCodec=avcodec_find_decoder(pFormatCtx->streams[videoStream_index]->codecpar->codec_id);
    if(pCodec==NULL)
        return -1; // Codec not found
 
    pCodecContext=avcodec_alloc_context3(pCodec);
    if (avcodec_parameters_to_context(pCodecContext, pFormatCtx->streams[videoStream_index]->codecpar)<0)
    {
      return -1;
    };

    // Open codec
    if(avcodec_open2(pCodecContext, pCodec,0)<0)
        return -1; // Could not open codec
 
    pFrame=av_frame_alloc();
    // Allocate an AVFrame structure
    pFrameRGB=av_frame_alloc();
    
    if(pFrameRGB==NULL||pFrame==NULL)
        return -1;
    
    // Determine required buffer size and allocate buffer
//    numBytes=avpicture_get_size(AV_PIX_FMT_RGB24, pCodecContext->width, pCodecContext->height);
    
    numBytes=av_image_get_buffer_size(AV_PIX_FMT_RGB24, pCodecContext->width, pCodecContext->height,1);
    buffer=(uint8_t*)malloc(numBytes);
    if (buffer==NULL) {
         printf("av malloc failed!\n");
    }
    // Assign appropriate parts of buffer to image planes in pFrameRGB
//    avpicture_fill((AVPicture *)pFrameRGB, buffer, AV_PIX_FMT_RGB24,
//                   pCodecContext->width, pCodecContext->height);
    
    av_image_fill_arrays(pFrameRGB->data,pFrameRGB->linesize,buffer, AV_PIX_FMT_RGB24,
                         pCodecContext->width, pCodecContext->height,1);
    // Read frames and save first five frames to disk
    pSwsCtx = sws_getContext(pCodecContext->width, pCodecContext->height, pCodecContext->pix_fmt, pCodecContext->width, pCodecContext->height, AV_PIX_FMT_BGR24, SWS_FAST_BILINEAR, NULL, NULL, NULL);
    
    i=0;
    j=0;
    int64_t read_pts=0;
    double video_time= av_q2d(pFormatCtx->streams[videoStream_index]->time_base);
    while (av_read_frame(pFormatCtx, &packet) >= 0) {
#if 1
        if (packet.stream_index == audioStream_index) {
            
            int got_frame=0;
            
            int ret=decode(pCodecContext, pFrame, &got_frame, &packet);
            
            printf("%s",av_err2str(ret));
            //printf("@_@ audio nb_frames:%lld  pos:%lld  pts:%lld dts:%lld  \n\n",nb_frames_audio,packet.pos,packet.pts,packet.dts);
            continue;
        }
#endif
        if (packet.stream_index == videoStream_index) {
          
#if 1
          if (avcodec_send_packet(pCodecContext, &packet)<0)
          {
              av_packet_unref(&packet);
              continue;
          }
            if (avcodec_receive_frame(pCodecContext, pFrame)<0) {
                av_packet_unref(&packet);
                 continue;
            }
            
             if (pFrame->key_frame) {
                
//                printf("key_frame packet NO:%d video packet pts:%lld dts:%lld duration:%lld pos:%lld size:%d data:%02X %02X %02X %02X %02X  \n",i,packet.pts,packet.dts,packet.duration,packet.pos,packet.size,packet.data[0],packet.data[1],packet.data[2],packet.data[3],packet.data[4]);
                pFrameRGB->pts=pFrame->pts;
                pFrameRGB->pkt_dts=pFrame->pkt_dts;
                pFrameRGB->key_frame=pFrame->key_frame;
                pFrameRGB->coded_picture_number=pFrame->coded_picture_number;
                pFrameRGB->display_picture_number=pFrame->display_picture_number;
                
                
                //转换图像格式，将解压出来的YUV420P的图像转换为BRG24的图像
                sws_scale(pSwsCtx, (const uint8_t* const*)pFrame->data, pFrame->linesize, 0, pCodecContext->height, pFrameRGB->data, pFrameRGB->linesize);
                //保存为bmp图
//           saveJPG(pFrameRGB, pCodecContext->width, pCodecContext->height, i,(pFrame->pts+pFrame->pkt_duration)*video_time*1000);
                //SavePPM(pFrameRGB, pCodecContext->width, pCodecContext->height, i);
                printf("key_frame NO:%d pts:%lld dts:%lld duration:%lld pos:%lld size:%d diff_pts:%lld video_time:%0.f type:%s \n\n\n\n",i,pFrame->pts,pFrame->pkt_dts,pFrame->pkt_duration,pFrame->pkt_pos,pFrame->pkt_size,pFrame->                                                                                            pts-read_pts,(pFrame->pts+pFrame->pkt_duration)*video_time*1000,getFrameType(pFrame->pict_type));
                 read_pts=pFrame->pts;
                 ++j;
               
            }
            else
            {
             printf("not key_frame NO:%d video packet pts:%lld dts:%lld duration:%lld pos:%lld size:%d video_time:%0.f type:%s \n",i,packet.pts,packet.dts,packet.duration,packet.pos,packet.size,(pFrame->pts+pFrame->pkt_duration)*video_time*1000,getFrameType(pFrame->pict_type));
            }
            i++;
         av_packet_unref(&packet);
            
#else
            //解码
           if  (avcodec_decode_video2(pCodecContext, pFrame, &frameFinished, &packet)<0)
               continue ;
            //一个完整的帧
            if (frameFinished) {
                ++frame_k;
                if (pFrame->key_frame) {
                    
                    printf("packet pts:%lld dts:%lld duration:%lld pos:%lld \n",packet.pts,packet.dts,packet.duration,packet.pos);
                    pFrameRGB->pts=pFrame->pts;
                    pFrameRGB->pkt_dts=pFrame->pkt_dts;
                    pFrameRGB->key_frame=pFrame->key_frame;
                    pFrameRGB->coded_picture_number=pFrame->coded_picture_number;
                    pFrameRGB->display_picture_number=pFrame->display_picture_number;
                    
                    
                    //转换图像格式，将解压出来的YUV420P的图像转换为BRG24的图像
                    sws_scale(pSwsCtx, (const uint8_t* const*)pFrame->data, pFrame->linesize, 0, pCodecContext->height, pFrameRGB->data, pFrameRGB->linesize);
                    //保存为bmp图
                    //saveJPG(pFrameRGB, pCodecContext->width, pCodecContext->height, i);
                    //SavePPM(pFrameRGB, pCodecContext->width, pCodecContext->height, i);
                    printf("key_frame:NO:%d pts:%lld dts:%lld\n\n",i,pFrame->pts,pFrame->pkt_dts);
                    
                    i++;
                }
            }
            av_free_packet(&packet);
#endif

        }
    }
    printf("frame key_frame:%d nb_frames:%lld",j,nb_frames);
    // Free the RGB image
    free(buffer);
    //free  buffer;
    av_free(pFrameRGB);
    // Free the YUV frame
    av_free(pFrame);
    // Close the codec
    avcodec_close(pCodecContext);
    // Close the video file

    avformat_free_context(pFormatCtx);
 
    return 0;  
}

#endif
